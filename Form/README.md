# BioAre · Speaker Feedback Intelligence (v3)

A GitHub Pages-ready subfolder for an existing website. **Do not replace the root `index.html` or root `manager.html`.**

## Files and URLs

```text
main-website/
├── index.html                   <- old main website, unchanged
├── manager.html                 <- old main manager, unchanged
└── bioare/
    ├── index.html               <- welcome / PDPA / 3-step survey
    ├── manager.html             <- BioAre Manager ONLY
    ├── assets/
    │   ├── config.js            <- public Supabase publishable key only
    │   ├── style.css
    │   ├── student.js
    │   └── manager.js
    ├── database/
    │   ├── install.sql          <- consolidated full install (run this)
    │   ├── 01_existing_core.sql
    │   ├── 02_school_aliases.sql
    │   ├── 03_new_features.sql
    │   └── 04_grant_manager.sql <- run after Auth user exists
    └── supabase/functions/bioare-insights/index.ts
```

Published via GitHub Pages: `/bioare/` and `/bioare/manager.html`. The Manager login email is `arewarin.biology@gmail.com` (password is **not** in code). Supabase URL is `https://ihmiqtwclnqrezsnswfz.supabase.co` and the public browser key is `sb_publishable_wODtFcX141odUfA1FxZckQ_OXXkOZLR`.

## Install

1. In Supabase Dashboard > **SQL Editor**, run **`database/install.sql`**. This combines the existing feedback table, school alias mappings and the ten-feature upgrade. The new schema does not drop old feedback. **Note:** the new consent validation requires deploying the updated student `index.html` and `assets/student.js` at the same time. Older forms using the same table cannot insert until updated.
2. Supabase Dashboard > **Authentication > Users**: create or confirm the user `arewarin.biology@gmail.com` with a password (do not put passwords in GitHub). **Run `database/04_grant_manager.sql`** to grant access. Passwords are never committed. If email confirmation is enabled, complete the corresponding email verification first.
3. Upload the entire `bioare` folder **alongside** the existing root website files to your GitHub repository, enable GitHub Pages, open `/bioare/`, then `/bioare/manager.html`.
4. **Test**: submit a test response, view it in BioAre Manager, create a session, open the QR link and submit a second response. Test PDPA acknowledgement, school merging and CSV export. Remove test responses via the Supabase Dashboard if needed.
5. Optional AI Insights: install Supabase CLI, deploy the function from the repo root `supabase/functions/bioare-insights` (or copy this function into your existing Supabase project's `supabase/functions` directory) and set server-side secret `OPENAI_API_KEY`. Never add it to HTML or GitHub. To deploy from a Supabase CLI project: `supabase functions deploy bioare-insights` and `supabase secrets set OPENAI_API_KEY=...`. The function requires a valid Auth JWT and checks admin membership before calling AI. Default model is `gpt-4.1-mini`; optional `OPENAI_MODEL` can override it. **AI is not enabled until this step is completed.**
6. Optional instant updates: turn on database replication for `public.speaker_feedback` under Supabase Realtime. The Manager always polls every ~45 seconds even without this.

## Implemented modules

1. **Lecture Sessions:** create/edit, open/close sessions, per-session questions and analytics; linked survey overrides student-typed school/grade/topic on the server.
2. **Smart QR:** unique link for each session; QR PNG download uses a browser QR library. Requires internet to load CDN resources.
3. **Smart School Directory:** autocomplete for public form, admin add/hide names, manually merge/unmerge aliases without altering original response text, similarity suggestions.
4. **Live Dashboard:** total responses, six average scores, pace/difficulty distribution, schools and sessions; 45-second refresh with optional realtime.
5. **Teaching Analytics:** breakdown across schools and sessions, filters.
6. **AI Feedback Insights:** optional Edge Function; sends **only whitelisted aggregate counts**, not names or raw student comments.
7. **One-click PDF:** manager report generates a print-friendly page, then opens browser Print > **Save as PDF**; CSV also available. No server-side PDF writer or extra PDF API key required.
8. **Feedback Wall:** administrator reviews/edits excerpts manually before publishing; site-wide switch defaults **off**. Does not automatically expose full student responses.
9. **Privacy & Data Rights:** editable privacy notice and version, recorded acknowledgement version and timestamp, optional names, receipt UUID, privacy request form, manager workflow, manual retention purge. **Important:** manual identity confirmation is necessary before fulfilling access/delete requests; a receipt UUID alone is not conclusive identity verification. Review language and retention with your data-protection adviser, especially for minors. Automated email replies are not included.
10. **Form Builder:** add and activate/deactivate optional questions (short/long/choice/scale), global or per-session, with results stored as JSON in `speaker_feedback.custom_answers`. Built-in six ratings and three feedback prompts remain unchanged.

## Security and limitations

- `sb_publishable_...` is public and safe in client code **only with RLS in place**. **Never** publish `service_role`, `sb_secret_*`, `OPENAI_API_KEY`, passwords or student response exports in GitHub.
- Anonymous website visitors can insert (but not select/update/delete) feedback. Admin access is checked with `speaker_feedback_admins` and Supabase Auth; SQL policies enforce permissions, not just UI restrictions.
- Published Wall excerpts are reviewed by the manager; avoid disclosing identifiers. Public sessions expose school and title while accepting responses.
- Browser-based anonymous submissions cannot completely prevent spam or multiple submissions. To harden for heavy public use, add bot protection/rate limiting using Edge Functions and CAPTCHA server verification.
- School similarity suggestions are **not automatic merges**; a manager confirms them.
- Reports and visual charts represent responses from participants only, not an unbiased study sample. The browser Manager fetches up to 20,000 records per table, warns if this cap is hit.
- The PDF action uses your browser's **Print / Save as PDF** menu; it does not directly download PDF bytes.
- This package has been syntax-checked and static-tested, but **has not** been run against the user's live Supabase project because access was not provided. Verify live end-to-end after SQL migration.

## Github Pages navigation

Main website link example:

```html
<a href="./bioare/">ประเมินวิทยากร BioAre</a>
<a href="./bioare/manager.html">จัดการ BioAre</a>
```

If GitHub Pages is set up as a project site, both links remain relative to your repo root.

## GDPR / PDPA handling

Publish a clear notice identifying the real data controller, contact details, processing purpose, optional/required fields, lawful basis, retention and rights. This package provides editable text, not an automatically legally compliant privacy policy. A student's age and the context of the school may affect consent/notification requirements; review prior to release.
