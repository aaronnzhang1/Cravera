// place-photo: turns a Google Places photo name into a short-lived image URL
// the app can load. The Places key stays on the server: Google's media
// endpoint needs it, but with skipHttpRedirect it answers with a
// googleusercontent.com link that doesn't contain the key.
//
// Same access rule as places-search: callers send a publishable key, checked
// in code because verify_jwt is off for these functions.

import { parsePublishableKeys } from "../places-search/logic.ts";

/** Only real Places photo names: no other path on Google's API is reachable. */
export const PHOTO_NAME = /^places\/[A-Za-z0-9_-]{1,300}\/photos\/[A-Za-z0-9_-]{1,1000}$/;
export const MAX_WIDTH_PX = 800;
const UPSTREAM_TIMEOUT_MS = 8000;

export type Env = {
  placesKey: string | undefined;
  publishableKeys: string | undefined;
};

type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** The image link Google returns must be https on googleusercontent.com. */
export function isSafePhotoUri(value: unknown): value is string {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && (url.hostname === "googleusercontent.com" ||
      url.hostname.endsWith(".googleusercontent.com"));
  } catch {
    return false;
  }
}

export async function handle(req: Request, env: Env, fetchFn: FetchFn): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "Use POST." });

  const allowed = parsePublishableKeys(env.publishableKeys);
  const apikey = req.headers.get("apikey");
  if (!apikey || !allowed.includes(apikey)) return json(401, { error: "Unauthorized." });

  if (!env.placesKey) {
    console.error("place-photo: GOOGLE_MAPS_API_KEY is not set");
    return json(500, { error: "Photos are not configured." });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Body must be valid JSON." });
  }
  const name = (body as { photoName?: unknown })?.photoName;
  if (typeof name !== "string" || !PHOTO_NAME.test(name)) {
    return json(400, { error: "photoName must be a Places photo name." });
  }

  const url = `https://places.googleapis.com/v1/${name}/media?maxWidthPx=${MAX_WIDTH_PX}&skipHttpRedirect=true`;
  let upstream: Response;
  try {
    upstream = await fetchFn(url, {
      method: "GET",
      headers: { "X-Goog-Api-Key": env.placesKey },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      redirect: "error",
    });
  } catch (e) {
    console.error("place-photo: upstream request failed", (e as Error)?.name);
    return json(502, { error: "Photo unavailable." });
  }
  if (!upstream.ok) {
    console.error("place-photo: upstream status", upstream.status);
    return json(502, { error: "Photo unavailable." });
  }

  let data: unknown;
  try {
    data = await upstream.json();
  } catch {
    return json(502, { error: "Photo unavailable." });
  }
  const photoUri = (data as { photoUri?: unknown })?.photoUri;
  // Never pass on a link that could point elsewhere or carry the key.
  if (!isSafePhotoUri(photoUri) || photoUri.includes(env.placesKey)) {
    console.error("place-photo: unexpected photoUri");
    return json(502, { error: "Photo unavailable." });
  }
  return json(200, { photoUri });
}
