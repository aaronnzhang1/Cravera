// Edge Function entry point. Logic and tests: logic.ts, logic.test.ts.
import { handle } from "./logic.ts";

Deno.serve((req) =>
  handle(
    req,
    {
      placesKey: Deno.env.get("GOOGLE_MAPS_API_KEY"),
      publishableKeys: Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
      geminiKey: Deno.env.get("GOOGLE_GEMINI_API_KEY"),
      geminiModel: Deno.env.get("GEMINI_MODEL"),
    },
    fetch,
  )
);
