// delete-account: deletes the caller's own account (App Store rule for apps
// with accounts). The caller is identified only by their access token, which
// Supabase Auth checks; any user ID in the request is ignored, so a client
// can never name someone else. The profile row goes with the auth user
// (ON DELETE CASCADE). The secret key never leaves the server.
//
// verify_jwt is off (like the other functions): this code checks the
// publishable key and the user token itself and fails closed.

import { parsePublishableKeys } from "../places-search/logic.ts";

export type Env = {
  supabaseUrl: string | undefined;
  publishableKeys: string | undefined;
  /** SUPABASE_SECRET_KEYS (JSON object/array or a plain key), server-side only. */
  secretKeys: string | undefined;
};

type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

const UPSTREAM_TIMEOUT_MS = 8000;
const USER_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/** The bearer token from the Authorization header, or null. */
export function bearer(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const match = /^Bearer\s+([A-Za-z0-9._-]{20,4096})$/.exec(header.trim());
  return match ? match[1] : null;
}

export async function handle(req: Request, env: Env, fetchFn: FetchFn): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "Use POST." });

  const apikey = req.headers.get("apikey");
  if (!apikey || !parsePublishableKeys(env.publishableKeys).includes(apikey)) {
    return json(401, { error: "Unauthorized." });
  }
  const token = bearer(req);
  if (!token) return json(401, { error: "Sign in first." });

  const [secret] = parsePublishableKeys(env.secretKeys);
  if (!env.supabaseUrl || !secret) {
    console.error("delete-account: SUPABASE_URL or SUPABASE_SECRET_KEYS is not set");
    return json(500, { error: "Account deletion is not configured." });
  }
  const base = env.supabaseUrl.replace(/\/+$/, "");

  // 1. Who is calling? Only Supabase Auth can say, from their own token.
  let userId: string;
  try {
    const res = await fetchFn(`${base}/auth/v1/user`, {
      method: "GET",
      headers: { apikey, Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    if (res.status === 401 || res.status === 403) return json(401, { error: "Sign in again." });
    if (!res.ok) {
      console.error("delete-account: user lookup status", res.status);
      return json(502, { error: "Couldn't delete the account. Try again." });
    }
    const id = ((await res.json()) as { id?: unknown })?.id;
    if (typeof id !== "string" || !USER_ID.test(id)) return json(401, { error: "Sign in again." });
    userId = id;
  } catch (e) {
    console.error("delete-account: user lookup failed", (e as Error)?.name);
    return json(502, { error: "Couldn't delete the account. Try again." });
  }

  // 2. Delete that user, and only that user.
  try {
    const res = await fetchFn(`${base}/auth/v1/admin/users/${userId}`, {
      method: "DELETE",
      headers: { apikey: secret, Authorization: `Bearer ${secret}` },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    if (!res.ok && res.status !== 404) {
      console.error("delete-account: delete status", res.status);
      return json(502, { error: "Couldn't delete the account. Try again." });
    }
  } catch (e) {
    console.error("delete-account: delete failed", (e as Error)?.name);
    return json(502, { error: "Couldn't delete the account. Try again." });
  }
  console.log("delete-account: deleted");
  return json(200, { deleted: true });
}
