// saved-places: fresh basics for the Saved hub list (TASK-004).
//
// Saved rows hold only place IDs (Google's terms don't allow storing names or
// addresses), so the list asks here each time it opens. One Place Details
// request per place with a small field mask (Google's Pro tier: name,
// address, location, address parts); full details load only when a place is
// tapped (place-details). The caller sends place IDs only: no user data
// reaches this function, so the publishable-key check is the gate, as for
// the other Places functions. A daily Pro quota in Google Cloud caps cost.

import { parsePublishableKeys } from "../places-search/logic.ts";
import { cleanText, PLACE_ID } from "../place-details/logic.ts";

export const MAX_PLACES = 50;
export const FIELD_MASK = "id,displayName,formattedAddress,location,addressComponents";
const UPSTREAM_TIMEOUT_MS = 8000;
/** At most this many Google requests at once. */
const CONCURRENCY = 6;

export type Env = { placesKey: string | undefined; publishableKeys: string | undefined };
type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

export type Basics =
  | { placeId: string; name: string; address: string | null; city: string | null; latitude: number | null; longitude: number | null }
  | { placeId: string; error: "not_found" | "unavailable" };

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** The city for grouping: locality, else postal town, else the county-level area. */
export function cityOf(components: unknown): string | null {
  if (!Array.isArray(components)) return null;
  for (const type of ["locality", "postal_town", "administrative_area_level_2"]) {
    const c = components.find((x) => Array.isArray(x?.types) && x.types.includes(type));
    const name = cleanText(c?.longText, 80);
    if (name) return name;
  }
  return null;
}

export function mapBasics(data: unknown, placeId: string): Basics {
  const d = (data ?? {}) as Record<string, unknown>;
  const name = cleanText((d.displayName as { text?: unknown })?.text, 120);
  if (!name) return { placeId, error: "unavailable" };
  const loc = d.location as { latitude?: unknown; longitude?: unknown } | undefined;
  const lat = typeof loc?.latitude === "number" && Math.abs(loc.latitude) <= 90 ? loc.latitude : null;
  const lng = typeof loc?.longitude === "number" && Math.abs(loc.longitude) <= 180 ? loc.longitude : null;
  return {
    placeId,
    name,
    address: cleanText(d.formattedAddress, 200),
    city: cityOf(d.addressComponents),
    latitude: lat !== null && lng !== null ? lat : null,
    longitude: lat !== null && lng !== null ? lng : null,
  };
}

async function one(placeId: string, key: string, fetchFn: FetchFn): Promise<Basics> {
  try {
    const res = await fetchFn(`https://places.googleapis.com/v1/places/${placeId}`, {
      method: "GET",
      headers: { "X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELD_MASK },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      redirect: "error",
    });
    if (res.status === 404) return { placeId, error: "not_found" };
    if (!res.ok) {
      console.error("saved-places: upstream status", res.status);
      return { placeId, error: "unavailable" };
    }
    return mapBasics(await res.json(), placeId);
  } catch (e) {
    console.error("saved-places: upstream request failed", (e as Error)?.name);
    return { placeId, error: "unavailable" };
  }
}

export async function handle(req: Request, env: Env, fetchFn: FetchFn): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "Use POST." });
  const allowed = parsePublishableKeys(env.publishableKeys);
  const apikey = req.headers.get("apikey");
  if (!apikey || !allowed.includes(apikey)) return json(401, { error: "Unauthorized." });
  if (!env.placesKey) {
    console.error("saved-places: GOOGLE_MAPS_API_KEY is not set");
    return json(500, { error: "Saved places are not configured." });
  }
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Body must be valid JSON." });
  }
  const ids = (body as { placeIds?: unknown })?.placeIds;
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > MAX_PLACES ||
      !ids.every((id) => typeof id === "string" && PLACE_ID.test(id))) {
    return json(400, { error: `placeIds must be 1 to ${MAX_PLACES} Places place IDs.` });
  }
  const unique = [...new Set(ids as string[])];
  const out: Basics[] = new Array(unique.length);
  let next = 0;
  const worker = async () => {
    while (next < unique.length) {
      const i = next++;
      out[i] = await one(unique[i], env.placesKey!, fetchFn);
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, unique.length) }, worker));
  return json(200, { places: out });
}
