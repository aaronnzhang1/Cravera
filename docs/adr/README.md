# Decision records

Read this index, then open only the records your task needs.

To add one, copy the shape of 0001 (title, Status, Date, Context, Decision, Consequences; leave out empty sections). Name it `NNNN-short-title.md` with the next number, and add a row below in the same PR. Never rewrite a decision: supersede it with a new record, and mark the old one `Superseded by NNNN` on its first line.

| # | Title | Status | Summary |
|---|---|---|---|
| [0001](0001-agent-workflow.md) | Agent workflow | Accepted | Claude builds, Codex reviews; the repo is the memory; the reason behind each rule |
| [0002](0002-stack.md) | Stack | Accepted | Flutter, Supabase, Gemini for parsing only, Google Places for data |
| [0003](0003-api-key-handling.md) | API key handling | Accepted | Google and Gemini keys live in Supabase Edge Functions, never in the app bundle |
| [0004](0004-resume-and-releases.md) | Resume, approval and releases | Accepted | `/resume` is the entry point; `Approved:` line on tasks; releases are tagged PRODUCT.md rows |
| [0005](0005-traceable-ai-summaries.md) | AI on the restaurant card | Accepted | Checked facts (Gemini picks fields, code words them) plus a labelled "Cravera's take" that may not state numbers, prices, links or hours (checked in code); details load for each place shown |
