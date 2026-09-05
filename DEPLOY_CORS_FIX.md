# AreWarin Tutor Application — CORS Fix

## Cause
The browser error is from the Edge Function gateway, not from Tailwind.
`submit-tutor-application` is a public form. If JWT verification is enabled, the
Supabase gateway can reject the browser's CORS OPTIONS/preflight before the
function code runs.

The frontend previously also sent the publishable key as `Authorization: Bearer ...`.
A Supabase `sb_publishable_...` key is not a user access-token JWT. The fixed
frontend therefore sends FormData without Authorization/apikey headers.

## 1. Replace files
- `tutor-apply/app.js`
- `supabase/functions/submit-tutor-application/index.ts`
- `supabase/config.toml`

## 2. Deploy the function
From the project root:

```bash
supabase login
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy submit-tutor-application --no-verify-jwt
```

The `--no-verify-jwt` flag is essential for this public application endpoint.

## 3. Verify deployment
Open this URL in a browser:

https://ihmiqtwclnqrezsnswfz.supabase.co/functions/v1/submit-tutor-application

Expected response:

```json
{"ok":true,"function":"submit-tutor-application","version":"v13-cors-fix"}
```

## 4. Verify CORS preflight (optional)

```bash
curl -i -X OPTIONS \
  'https://ihmiqtwclnqrezsnswfz.supabase.co/functions/v1/submit-tutor-application' \
  -H 'Origin: https://siriphat1.github.io' \
  -H 'Access-Control-Request-Method: POST'
```

Expected:
- HTTP 204
- `access-control-allow-origin: *`
- `access-control-allow-methods: GET, POST, OPTIONS`

## 5. Publish GitHub Pages
Upload the fixed `tutor-apply/app.js` to the repository and wait for GitHub Pages
to deploy. Then hard refresh with Ctrl+Shift+R.

## Tailwind warning
`cdn.tailwindcss.com should not be used in production` is only a warning and is
not the cause of the failed tutor application submission. It can be migrated to
a compiled Tailwind build separately.
