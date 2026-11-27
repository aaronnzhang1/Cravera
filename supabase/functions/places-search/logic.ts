// places-search: turns a craving + location into open-now restaurants from
// Google Places Text Search (New). Pure logic lives here so it can be tested
// without Deno or the network; index.ts only wires in env vars and fetch.
//
// Rules (AGENTS.md): every restaurant field comes from Google Places, the
// search is always open-now, and the Places key never leaves the server.
// Gemini (gemini.ts) only shapes the search text and the order; open-now, the
// radius and the restaurant check are set here, after it, in code.

import {
  type Candidate,
  curate,
  DEFAULT_GEMINI_MODEL,
  fallbackIntent,
  type GeminiConfig,
  type Intent,
  understand,
  validateIntent,
} from "./gemini.ts";

export const PLACES_URL = "https://places.googleapis.com/v1/places:searchText";

// Only the fields the card needs. Fewer fields = cheaper, and nothing extra leaks.
export const FIELD_MASK = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.location",
  "places.priceLevel",
  "places.rating",
  "places.primaryTypeDisplayName",
  "places.types",
  "places.photos",
  "places.currentOpeningHours.openNow",
].join(",");

export const DEFAULT_RADIUS_M = 5000;
export const MIN_RADIUS_M = 500;
export const MAX_RADIUS_M = 20000;
export const MAX_QUERY_LENGTH = 200;
export const MAX_ABS_LATITUDE = 85;
const UPSTREAM_TIMEOUT_MS = 8000;
/**
 * The whole request must answer within this, below the app's 15 s timeout:
 * a step that wouldn't fit is skipped (curation, the relaxed retry), so a
 * slow Gemini never costs the guest a result Places already gave.
 */
export const REQUEST_BUDGET_MS = 11_000;
const MIN_CURATE_MS = 1500;
/** "Close by" when the place is within this. */
const NEAR_M = 1500;
const HIGHLY_RATED = 4.5;
const EARTH_RADIUS_M = 6_371_000;

export type SearchInput = {
  query: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
  /** The intent of the search being refined, from the app. Untrusted: validated. */
  previousIntent: Intent | null;
  /** The guest's local hour (0-23), so "late-night" or "breakfast" make sense. */
  localHour: number | null;
};

export type RestaurantResult = {
  placeId: string;
  name: string;
  address: string | null;
  cuisine: string | null;
  priceLevel: number | null;
  rating: number | null;
  distanceMeters: number;
  photoName: string | null;
  /** Google requires showing the photo author's name (and link) with the photo. */
  photoAuthor: string | null;
  photoAuthorUri: string | null;
  /** Every author of the photo, with link and avatar when Google gives them (TASK-UI-2). */
  photoAuthors: PhotoAuthor[];
  /** The photo on Google Maps; Google requires a link to it. */
  photoMapsUri: string | null;
  latitude: number;
  longitude: number;
  /**
   * Why this pick, built in code from this result's Places facts and the
   * intent (price, distance, rating). Never text from the model.
   */
  reasons: string[];
};

export type Env = {
  placesKey: string | undefined;
  publishableKeys: string | undefined;
  /** Optional: without it, search uses the raw text and Places order. */
  geminiKey?: string | undefined;
  geminiModel?: string | undefined;
  /** Milliseconds clock; tests replace it. */
  now?: () => number;
};

type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

/** Returns the input if valid, or an error message for a 400. */
export function parseInput(body: unknown): SearchInput | string {
  if (typeof body !== "object" || body === null) return "Body must be a JSON object.";
  const b = body as Record<string, unknown>;
  const query = typeof b.query === "string" ? b.query.trim() : "";
  if (query.length === 0) return "query is required.";
  if (query.length > MAX_QUERY_LENGTH) return `query must be at most ${MAX_QUERY_LENGTH} characters.`;
  const { latitude, longitude } = b;
  // Near a pole the search box would be wider than Google allows (180°), and
  // there are no restaurants there, so those searches are refused.
  if (typeof latitude !== "number" || !Number.isFinite(latitude) || Math.abs(latitude) > MAX_ABS_LATITUDE) {
    return `latitude must be a number between -${MAX_ABS_LATITUDE} and ${MAX_ABS_LATITUDE}.`;
  }
  if (typeof longitude !== "number" || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return "longitude must be a number between -180 and 180.";
  }
  let radiusMeters = DEFAULT_RADIUS_M;
  if (b.radiusMeters !== undefined) {
    if (typeof b.radiusMeters !== "number" || !Number.isFinite(b.radiusMeters)) {
      return "radiusMeters must be a number.";
    }
    radiusMeters = Math.min(MAX_RADIUS_M, Math.max(MIN_RADIUS_M, b.radiusMeters));
  }
  // Both are optional hints: a bad value is ignored, not an error.
  const previousIntent = b.previousIntent === undefined ? null : validateIntent(b.previousIntent);
  const localHour = Number.isInteger(b.localHour) && (b.localHour as number) >= 0 && (b.localHour as number) <= 23
    ? b.localHour as number
    : null;
  return { query, latitude, longitude, radiusMeters, previousIntent, localHour };
}

function wrapLongitude(lng: number): number {
  return ((((lng + 180) % 360) + 360) % 360) - 180;
}

/**
 * Text Search (New) only *restricts* to a rectangle, so we send the box around
 * the circle and then drop anything outside the circle in [mapPlaces].
 */
/**
 * Only the intent's search text goes to Places. Its type, price and distance
 * steer curation instead of filtering here, so a filter can never turn a
 * match into "nothing open", and each search stays one Places call.
 */
export function buildRequestBody(input: SearchInput, intent: Intent = fallbackIntent(input.query)) {
  // Same sphere as distanceMeters, plus 1% margin, so the box always holds the
  // whole circle; mapPlaces then drops the corners.
  const angular = (input.radiusMeters * 1.01) / EARTH_RADIUS_M;
  const toDeg = (r: number) => (r * 180) / Math.PI;
  const dLat = toDeg(angular);
  const cosLat = Math.cos((input.latitude * Math.PI) / 180);
  const dLng = Math.sin(angular) >= cosLat ? 179 : Math.min(toDeg(Math.asin(Math.sin(angular) / cosLat)), 179);
  return {
    textQuery: intent.textQuery,
    includedType: "restaurant",
    // Without this, Google may skip the type filter (e.g. for an address query).
    strictTypeFiltering: true,
    openNow: true,
    pageSize: 20,
    locationRestriction: {
      rectangle: {
        low: {
          latitude: Math.max(-90, input.latitude - dLat),
          longitude: wrapLongitude(input.longitude - dLng),
        },
        high: {
          latitude: Math.min(90, input.latitude + dLat),
          longitude: wrapLongitude(input.longitude + dLng),
        },
      },
    },
  };
}

/** Great-circle distance in meters. */
export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = EARTH_RADIUS_M;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}

const PRICE_LEVELS: Record<string, number> = {
  PRICE_LEVEL_FREE: 0,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

/** Restaurant types in Places are "restaurant" or "<kind>_restaurant". */
export function isRestaurant(types: unknown): boolean {
  return Array.isArray(types) &&
    types.some((t) => t === "restaurant" || (typeof t === "string" && t.endsWith("_restaurant")));
}

/**
 * Maps the Places response to card data. Deny by default: a place is kept
 * only if Places says it is open now, it is a restaurant, and it is inside
 * the search circle.
 * A missing optional field becomes null, never a made-up value.
 */
export function mapPlaces(data: unknown, input: SearchInput): RestaurantResult[] {
  const places = (data as { places?: unknown })?.places;
  if (!Array.isArray(places)) return [];
  const results: RestaurantResult[] = [];
  for (const p of places) {
    const id = typeof p?.id === "string" ? p.id : null;
    const name = typeof p?.displayName?.text === "string" ? p.displayName.text : null;
    const lat = p?.location?.latitude;
    const lng = p?.location?.longitude;
    if (!id || !name || typeof lat !== "number" || typeof lng !== "number") continue;
    if (p?.currentOpeningHours?.openNow !== true) continue;
    if (!isRestaurant(p?.types)) continue;
    const distance = distanceMeters(input.latitude, input.longitude, lat, lng);
    if (distance > input.radiusMeters) continue;
    results.push({
      placeId: id,
      name,
      address: typeof p.formattedAddress === "string" ? p.formattedAddress : null,
      cuisine: typeof p.primaryTypeDisplayName?.text === "string" ? p.primaryTypeDisplayName.text : null,
      priceLevel: PRICE_LEVELS[p.priceLevel] ?? null,
      rating: typeof p.rating === "number" ? p.rating : null,
      distanceMeters: Math.round(distance),
      photoName: typeof p.photos?.[0]?.name === "string" ? p.photos[0].name : null,
      ...photoAuthor(p.photos?.[0]),
      photoAuthors: photoAuthors(p.photos?.[0]),
      photoMapsUri: photoMapsUri(p.photos?.[0]),
      latitude: lat,
      longitude: lng,
      reasons: [],
    });
  }
  return results;
}

export type PhotoAuthor = { name: string; uri: string | null; avatarUri: string | null };

/** At most this many authors are sent; a Places photo normally has one. */
export const MAX_PHOTO_AUTHORS = 3;

/** An https URL (Google sends some as "//host/..."), optionally only on [hosts] or their subdomains. */
export function httpsUrl(value: unknown, hosts?: string[]): string | null {
  if (typeof value !== "string") return null;
  try {
    const parsed = new URL(value.startsWith("//") ? `https:${value}` : value);
    if (parsed.protocol !== "https:") return null;
    if (hosts && !hosts.some((h) => parsed.hostname === h || parsed.hostname.endsWith(`.${h}`))) return null;
    return parsed.toString();
  } catch {
    return null;
  }
}

/** Every author attribution of a photo that has a name: links only if https, avatars only from Google's image host. */
export function photoAuthors(photo: unknown): PhotoAuthor[] {
  const list = (photo as { authorAttributions?: unknown })?.authorAttributions;
  if (!Array.isArray(list)) return [];
  const authors: PhotoAuthor[] = [];
  for (const a of list as { displayName?: unknown; uri?: unknown; photoUri?: unknown }[]) {
    const name = typeof a?.displayName === "string" ? a.displayName.trim() : "";
    if (!name) continue;
    authors.push({ name, uri: httpsUrl(a.uri), avatarUri: httpsUrl(a.photoUri, ["googleusercontent.com"]) });
    if (authors.length === MAX_PHOTO_AUTHORS) break;
  }
  return authors;
}

/** The first author of a photo (kept for app builds from before TASK-UI-2). */
export function photoAuthor(photo: unknown): { photoAuthor: string | null; photoAuthorUri: string | null } {
  const [first] = photoAuthors(photo);
  return { photoAuthor: first?.name ?? null, photoAuthorUri: first?.uri ?? null };
}

/** The photo's page on Google Maps, only if it is an https Google link. */
export function photoMapsUri(photo: unknown): string | null {
  return httpsUrl((photo as { googleMapsUri?: unknown })?.googleMapsUri, ["google.com", "maps.app.goo.gl"]);
}

/** SUPABASE_PUBLISHABLE_KEYS may be a JSON object/array of keys or a plain string. */
export function parsePublishableKeys(raw: string | undefined): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    const values = Array.isArray(parsed) ? parsed : typeof parsed === "object" && parsed ? Object.values(parsed) : [parsed];
    return values.filter((v): v is string => typeof v === "string" && v.length > 0);
  } catch {
    return raw.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
  }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handle(req: Request, env: Env, fetchFn: FetchFn): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "Use POST." });

  // The gateway's JWT check doesn't understand publishable keys, so the
  // function checks the key itself. Fails closed if none are configured.
  const allowed = parsePublishableKeys(env.publishableKeys);
  const apikey = req.headers.get("apikey");
  if (!apikey || !allowed.includes(apikey)) return json(401, { error: "Unauthorized." });

  if (!env.placesKey) {
    console.error("places-search: GOOGLE_MAPS_API_KEY is not set");
    return json(500, { error: "Search is not configured." });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Body must be valid JSON." });
  }
  const input = parseInput(body);
  if (typeof input === "string") return json(400, { error: input });

  const now = env.now ?? Date.now;
  const deadline = now() + REQUEST_BUDGET_MS;
  const left = () => deadline - now();
  const gemini: GeminiConfig | null = env.geminiKey
    ? { key: env.geminiKey, model: env.geminiModel || DEFAULT_GEMINI_MODEL, fetchFn }
    : null;

  // 1. Understand. Without Gemini, or if it fails, use the raw text; when
  //    refining, the new words always fit and the previous text is shortened.
  const understood = gemini ? await understand(gemini, input.query, input.previousIntent, input.localHour, left()) : null;
  // A refine that falls back keeps the previous (validated) filters.
  const intent = understood ??
    (input.previousIntent ? { ...input.previousIntent, textQuery: fallbackText(input) } : fallbackIntent(input.query));

  // 2. Search: one Places call, with only the intent's text.
  let results = await searchPlaces(input, intent, env.placesKey, fetchFn, Math.min(UPSTREAM_TIMEOUT_MS, left()));
  if (results === null) return json(502, { error: "Search failed. Try again." });

  let curation = "skipped";
  // 3. Curate, only if Gemini understood the craving and there is time. It
  //    sees only Places data under refs we choose and returns an order; if
  //    it fails, Places order stays.
  if (gemini && understood && results.length > 1 && left() >= MIN_CURATE_MS) {
    const candidates: Candidate[] = results.map((r, i) => ({
      ref: `c${i + 1}`,
      name: r.name,
      cuisine: r.cuisine,
      priceLevel: r.priceLevel,
      rating: r.rating,
      distanceMeters: r.distanceMeters,
    }));
    const order = await curate(gemini, intent, candidates, left() - 500);
    curation = order ? "ok" : "fallback";
    if (order) {
      const byRef = new Map(candidates.map((c, i) => [c.ref, results![i]]));
      results = order.map((ref) => byRef.get(ref)!);
    }
  }

  // Outcomes only (no craving, intent or places), to see how Gemini is doing.
  console.log("places-search: understand", gemini ? (understood ? "ok" : "fallback") : "off", "curate", curation, "results", results.length);

  // 4. Explain, from Places facts only.
  results = results.map((r) => ({ ...r, reasons: reasonsFor(r) }));
  return json(200, { results, intent });
}

/** The search text when Gemini didn't answer: the craving, or the previous text plus the refinement. */
export function fallbackText(input: SearchInput): string {
  if (!input.previousIntent) return input.query;
  const room = MAX_QUERY_LENGTH - input.query.length - 1;
  if (room <= 0) return input.query;
  return `${input.previousIntent.textQuery.slice(0, room).trim()} ${input.query}`;
}

/**
 * "Why this pick", from facts Places gave for this place only. Fixed labels
 * in code: the model can't add, word or influence them (it never decides
 * what the guest "asked for" on the card).
 */
export function reasonsFor(r: RestaurantResult): string[] {
  const reasons: string[] = [];
  if (r.priceLevel !== null && r.priceLevel <= 1) reasons.push("Budget-friendly");
  if (r.distanceMeters <= NEAR_M) reasons.push("Close by");
  if (r.rating !== null && r.rating >= HIGHLY_RATED) reasons.push("Highly rated");
  return reasons;
}

/** One Places call. Returns null on any upstream failure. */
async function searchPlaces(
  input: SearchInput,
  intent: Intent,
  placesKey: string,
  fetchFn: FetchFn,
  timeoutMs: number,
): Promise<RestaurantResult[] | null> {
  if (timeoutMs <= 0) return null;
  let upstream: Response;
  try {
    upstream = await fetchFn(PLACES_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": placesKey,
        "X-Goog-FieldMask": FIELD_MASK,
      },
      body: JSON.stringify(buildRequestBody(input, intent)),
      signal: AbortSignal.timeout(timeoutMs),
      // A redirect could replay the craving and location elsewhere: fail instead.
      redirect: "error",
    });
  } catch (e) {
    // Never log the query or location: they are the user's data.
    console.error("places-search: upstream request failed", (e as Error)?.name);
    return null;
  }
  if (!upstream.ok) {
    console.error("places-search: upstream status", upstream.status);
    return null;
  }
  try {
    return mapPlaces(await upstream.json(), input);
  } catch {
    console.error("places-search: upstream returned invalid JSON");
    return null;
  }
}
