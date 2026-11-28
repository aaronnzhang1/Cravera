// Edge Function entry point. Logic and tests: logic.ts, logic.test.ts.
import { handle } from "./logic.ts";

Deno.serve((req) =>
  handle(
    req,
    {
      supabaseUrl: Deno.env.get("SUPABASE_URL"),
      placesKey: Deno.env.get("GOOGLE_MAPS_API_KEY"),
      publishableKeys: Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
    },
    fetch,
  )
);
