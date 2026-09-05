-- Run AFTER creating the Manager user in Supabase Authentication > Users.
-- Change the email below if needed.
insert into public.profiles (id, display_name, role)
select id, 'AreWarin Admin', 'admin'
from auth.users
where lower(email) = lower('arewarin.biology@gmail.com')
on conflict (id) do update
set display_name = excluded.display_name,
    role = 'admin';
