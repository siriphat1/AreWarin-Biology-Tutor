# Tutor OS V14 — Quick Setup

## Existing AreWarin V13 Supabase
1. Open Supabase → SQL Editor.
2. Run `supabase/V14_EXISTING_PROJECT_UPGRADE.sql` once.
3. Upload the whole V14 web folder to GitHub Pages.
4. Logout from Manager/Tutor OS and login again.
5. Open `/tutor-os/`.

The current Manager/Admin role is automatically copied into `os_staff_profiles` as `admin`.

## Add a tutor account
Create the account in Supabase Authentication first, then in Tutor OS:
`Team & เนื้อหา → Staff & สิทธิ์ → ให้สิทธิ์` and paste the Auth UID.

## Fresh Supabase
Run only `supabase/AREWARIN_FULL_SETUP_V14.sql`.

## Public Edge Functions
Deploy/redeploy with JWT verification disabled:

```bash
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy create-enrollment --no-verify-jwt
supabase functions deploy get-receipt --no-verify-jwt
supabase functions deploy submit-tutor-application --no-verify-jwt
```

## URLs
- `/` Enrollment / Renewal
- `/manager/` Manager
- `/tutor-os/` Tutor OS
- `/tutor-os/staff/` Tutor staff workspace shortcuts
- `/tutor-apply/` Tutor Application TH/EN
- `/reviews/` Reviews
