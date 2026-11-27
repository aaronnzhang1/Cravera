// Edge Function entry point. Logic and tests: logic.ts, logic.test.ts.
import { handle } from "./logic.ts";

Deno.serve((req) =>
  handle(
    req,
    {
      supabaseUrl: Deno.env.get("SUPABASE_URL"),
      publishableKeys: Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
      secretKeys: Deno.env.get("SUPABASE_SECRET_KEYS"),
    },
    fetch,
  )
);
