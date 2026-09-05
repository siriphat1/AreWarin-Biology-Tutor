AREWARIN MANAGER ROLE FIX

1) Upload/replace config.js at project root.
2) Upload/replace manager/app.js.
3) In Supabase SQL Editor run FIX_ADMIN_ROLE.sql in full.
4) The final result must show:
   auth_user_found = true
   profile_found   = true
   profile_role    = admin
5) Sign out / hard refresh (Ctrl+Shift+R) / sign in again.

If auth_user_found = false, run CHECK_AUTH_USERS.sql and use the exact email shown there.
