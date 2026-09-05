# Supabase connection

Project URL has been configured in `config.js`.
Project ref: `ihmiqtwclnqrezsnswfz`

The browser uses the Supabase publishable key from `config.js`.
Do not place a `service_role` / secret key in any frontend file or GitHub public source.

Next required steps for a new project:
1. Run `supabase/AREWARIN_FULL_SETUP.sql` in Supabase SQL Editor.
2. Create an Admin user in Supabase Authentication.
3. Run `supabase/PROMOTE_ADMIN.sql` after changing the email if needed.
4. Deploy Edge Functions:
   - `create-enrollment`
   - `get-receipt`

## Renewal V11 upgrade
For the current existing project, run `supabase/EXISTING_STUDENT_RENEWAL_UPGRADE.sql` once and redeploy `create-enrollment`.
