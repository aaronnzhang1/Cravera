// place-details: what the smart card shows about one place (TASK-UI-4).
// Called only when the guest opens a card, never during search, so search
// keeps its budget and the pricier Places fields are paid for only on open.
//
// Every value returned comes from Google Places and is checked here: links
// must be https on the expected hosts, text is trimmed and capped, booleans
// are passed only when Places reports them. Nothing is filled in.
//
// Same access rule as places-search: callers send a publishable key, checked
// in code because verify_jwt is off for these functions.

import { httpsUrl, parsePublishableKeys, photoAuthors, type PhotoAuthor } from "../places-search/logic.ts";
import { PHOTO_NAME } from "../place-photo/logic.ts";

export const PLACE_ID = /^[A-Za-z0-9_-]{1,300}$/;
export const MAX_PHOTOS = 5;
export const MAX_REVIEWS = 5;
export const MAX_TEXT = 1500;
const UPSTREAM_TIMEOUT_MS = 8000;

/** Places attributes the card may show, in the order it shows them. */
export const ATTRIBUTES = [
  "takeout",
  "delivery",
  "dineIn",
  "servesVegetarianFood",
  "outdoorSeating",
  "goodForGroups",
  "servesBeer",
  "servesWine",
] as const;

export const FIELD_MASK = [
  "id",
  "photos",
  "reviews",
  "editorialSummary",
  "reviewSummary",
  "websiteUri",
  "googleMapsUri",
  ...ATTRIBUTES,
].join(",");

export type Env = {
  placesKey: string | undefined;
  publishableKeys: string | undefined;
};

type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

export type DetailPhoto = { name: string; authors: PhotoAuthor[]; mapsUri: string | null };
export type DetailReview = {
  authorName: string;
  authorUri: string | null;
  authorPhotoUri: string | null;
  rating: number | null;
  relativeTime: string | null;
  text: string;
  mapsUri: string | null;
};
export type Details = {
  placeId: string;
  photos: DetailPhoto[];
  reviews: DetailReview[];
  editorialSummary: string | null;
  reviewSummary: { text: string; disclosure: string | null } | null;
  websiteUri: string | null;
  mapsUri: string | null;
  attributes: Partial<Record<(typeof ATTRIBUTES)[number], boolean>>;
};

const GOOGLE_HOSTS = ["google.com", "maps.app.goo.gl"];

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Trimmed text, capped at [max] characters; null when empty or not a string. */
export function cleanText(value: unknown, max = MAX_TEXT): string | null {
  if (typeof value !== "string") return null;
  const t = value.trim();
  if (!t) return null;
  return t.length > max ? `${t.slice(0, max - 1).trimEnd()}…` : t;
}

/** Places sends localized text as { text, languageCode }. */
function localized(value: unknown): string | null {
  return cleanText((value as { text?: unknown })?.text);
}

/** A website link: http or https only (many restaurant sites are still http). */
export function webUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  try {
    const u = new URL(value);
    return u.protocol === "https:" || u.protocol === "http:" ? u.toString() : null;
  } catch {
    return null;
  }
}

export function mapDetails(data: unknown, placeId: string): Details {
  const d = (data ?? {}) as Record<string, unknown>;

  const photos: DetailPhoto[] = [];
  for (const p of Array.isArray(d.photos) ? d.photos : []) {
    if (photos.length >= MAX_PHOTOS) break;
    const name = (p as { name?: unknown })?.name;
    if (typeof name !== "string" || !PHOTO_NAME.test(name)) continue;
    // Google requires crediting the photo's authors; a photo without one isn't shown.
    const authors = photoAuthors(p);
    if (authors.length === 0) continue;
    photos.push({ name, authors, mapsUri: httpsUrl((p as { googleMapsUri?: unknown }).googleMapsUri, GOOGLE_HOSTS) });
  }

  const reviews: DetailReview[] = [];
  for (const r of Array.isArray(d.reviews) ? d.reviews : []) {
    if (reviews.length >= MAX_REVIEWS) break;
    const rv = r as Record<string, unknown>;
    const author = rv.authorAttribution as { displayName?: unknown; uri?: unknown; photoUri?: unknown } | undefined;
    const authorName = cleanText(author?.displayName, 100);
    const text = localized(rv.text) ?? localized(rv.originalText);
    if (!authorName || !text) continue;
    const rating = typeof rv.rating === "number" && rv.rating >= 1 && rv.rating <= 5 ? rv.rating : null;
    reviews.push({
      authorName,
      authorUri: httpsUrl(author?.uri),
      authorPhotoUri: httpsUrl(author?.photoUri, ["googleusercontent.com"]),
      rating,
      relativeTime: cleanText(rv.relativePublishTimeDescription, 60),
      text,
      mapsUri: httpsUrl(rv.googleMapsUri, GOOGLE_HOSTS),
    });
  }

  const summary = d.reviewSummary as { text?: unknown; disclosureText?: unknown } | undefined;
  const summaryText = localized(summary?.text);

  const attributes: Details["attributes"] = {};
  for (const a of ATTRIBUTES) {
    if (typeof d[a] === "boolean") attributes[a] = d[a] as boolean;
  }

  return {
    placeId,
    photos,
    reviews,
    editorialSummary: localized(d.editorialSummary),
    reviewSummary: summaryText ? { text: summaryText, disclosure: localized(summary?.disclosureText) } : null,
    websiteUri: webUrl(d.websiteUri),
    mapsUri: httpsUrl(d.googleMapsUri, GOOGLE_HOSTS),
    attributes,
  };
}

export async function handle(req: Request, env: Env, fetchFn: FetchFn): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "Use POST." });

  const allowed = parsePublishableKeys(env.publishableKeys);
  const apikey = req.headers.get("apikey");
  if (!apikey || !allowed.includes(apikey)) return json(401, { error: "Unauthorized." });

  if (!env.placesKey) {
    console.error("place-details: GOOGLE_MAPS_API_KEY is not set");
    return json(500, { error: "Details are not configured." });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Body must be valid JSON." });
  }
  const placeId = (body as { placeId?: unknown })?.placeId;
  if (typeof placeId !== "string" || !PLACE_ID.test(placeId)) {
    return json(400, { error: "placeId must be a Places place ID." });
  }

  let upstream: Response;
  try {
    upstream = await fetchFn(`https://places.googleapis.com/v1/places/${placeId}`, {
      method: "GET",
      headers: { "X-Goog-Api-Key": env.placesKey, "X-Goog-FieldMask": FIELD_MASK },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      redirect: "error",
    });
  } catch (e) {
    console.error("place-details: upstream request failed", (e as Error)?.name);
    return json(502, { error: "Details unavailable." });
  }
  if (upstream.status === 404) return json(404, { error: "Place not found." });
  if (!upstream.ok) {
    // Status only: never the place ID or Google's body.
    console.error("place-details: upstream status", upstream.status);
    return json(502, { error: "Details unavailable." });
  }

  let data: unknown;
  try {
    data = await upstream.json();
  } catch {
    return json(502, { error: "Details unavailable." });
  }
  return json(200, mapDetails(data, placeId));
}
