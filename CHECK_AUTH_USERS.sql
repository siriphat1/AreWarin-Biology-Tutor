-- Use this only if FIX_ADMIN_ROLE.sql reports auth_user_found = false.
-- It shows the exact email stored in Supabase Authentication.
select id, email, email_confirmed_at, created_at
from auth.users
order by created_at desc;
