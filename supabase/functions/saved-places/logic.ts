// saved-places: fresh basics for the Saved hub list (TASK-004).
//
// Saved rows hold only place IDs (Google's terms don't allow storing names or
// addresses), so the list asks here each time it opens. The caller sends no
// place IDs: the function reads the caller's own saved rows with their access
// token, so RLS decides which places are looked up, and only signed-in people
// with saved places can spend Places quota. One Place Details request per
// place with a small field mask (Google's Pro tier: name, address, location,
// address parts), at most 50, within a deadline shorter than the app's
// timeout; full details load only when a place is tapped (place-details).

import { parsePublishableKeys } from "../places-search/logic.ts";
import { cleanText, PLACE_ID } from "../place-details/logic.ts";
import { bearer } from "../delete-account/logic.ts";

export const MAX_PLACES = 50;
export const FIELD_MASK = "id,displayName,formattedAddress,location,addressComponents";
const UPSTREAM_TIMEOUT_MS = 8000;
/** The whole answer, under the app's 15 s timeout: unfinished places come back unavailable. */
export const DEADLINE_MS = 10_000;
/** At most this many Google requests at once. */
const CONCURRENCY = 6;

export type Env = { supabaseUrl: string | undefined; placesKey: string | undefined; publishableKeys: string | undefined };
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

async function one(placeId: string, key: string, fetchFn: FetchFn, signal: AbortSignal): Promise<Basics> {
  try {
    const res = await fetchFn(`https://places.googleapis.com/v1/places/${placeId}`, {
      method: "GET",
      headers: { "X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELD_MASK },
      signal: AbortSignal.any([AbortSignal.timeout(UPSTREAM_TIMEOUT_MS), signal]),
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

/** The caller's own saved place IDs, newest first, read with their token (RLS). */
async function ownPlaceIds(base: string, apikey: string, token: string, fetchFn: FetchFn, timeoutMs: number): Promise<string[] | "unauthorized" | null> {
  try {
    const res = await fetchFn(`${base}/rest/v1/saved_places?select=place_id&order=created_at.desc&limit=${MAX_PLACES}`, {
      method: "GET",
      headers: { apikey, Authorization: `Bearer ${token}`, Accept: "application/json" },
      signal: AbortSignal.timeout(Math.max(1, Math.min(UPSTREAM_TIMEOUT_MS, timeoutMs))),
      redirect: "error",
    });
    if (res.status === 401 || res.status === 403) return "unauthorized";
    if (!res.ok) {
      console.error("saved-places: rows status", res.status);
      return null;
    }
    const rows = await res.json();
    if (!Array.isArray(rows)) return null;
    return [...new Set(rows.map((r) => r?.place_id).filter((id): id is string => typeof id === "string" && PLACE_ID.test(id)))];
  } catch (e) {
    console.error("saved-places: rows request failed", (e as Error)?.name);
    return null;
  }
}

export async function handle(req: Request, env: Env, fetchFn: FetchFn, deadlineMs = DEADLINE_MS): Promise<Response> {
  // One deadline for the whole request, database read included.
  const started = Date.now();
  const left = () => deadlineMs - (Date.now() - started);
  if (req.method !== "POST") return json(405, { error: "Use POST." });
  const apikey = req.headers.get("apikey");
  if (!apikey || !parsePublishableKeys(env.publishableKeys).includes(apikey)) return json(401, { error: "Unauthorized." });
  const token = bearer(req);
  if (!token) return json(401, { error: "Sign in first." });
  if (!env.placesKey || !env.supabaseUrl) {
    console.error("saved-places: GOOGLE_MAPS_API_KEY or SUPABASE_URL is not set");
    return json(500, { error: "Saved places are not configured." });
  }
  const ids = await ownPlaceIds(env.supabaseUrl.replace(/\/+$/, ""), apikey, token, fetchFn, left());
  if (ids === "unauthorized") return json(401, { error: "Sign in again." });
  if (ids === null) return json(502, { error: "Couldn't read your saved places." });

  const out: Basics[] = ids.map((placeId) => ({ placeId, error: "unavailable" as const }));
  const stop = new AbortController();
  let next = 0;
  const worker = async () => {
    while (next < ids.length && !stop.signal.aborted) {
      const i = next++;
      const b = await one(ids[i], env.placesKey!, fetchFn, stop.signal);
      if (!stop.signal.aborted) out[i] = b;
    }
  };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<void>((resolve) => {
    timer = setTimeout(() => {
      stop.abort();
      resolve();
    }, Math.max(0, left()));
  });
  await Promise.race([Promise.all(Array.from({ length: Math.min(CONCURRENCY, ids.length) }, worker)), deadline]);
  clearTimeout(timer);
  stop.abort(); // nothing more after the answer
  return json(200, { places: out });
}
