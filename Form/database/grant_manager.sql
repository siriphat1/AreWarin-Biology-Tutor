-- STEP 1: In Supabase > Authentication > Users, create a user with email/password.
-- STEP 2: Replace the email below with that user's real email.
-- STEP 3: Run this SQL in SQL Editor with owner rights.
-- Do NOT put a real password in SQL, HTML, JavaScript, or GitHub.

DO $$
DECLARE
  admin_email text := 'arewarin.biology@gmail.com';  -- Supabase Auth admin email
  admin_uid uuid;
BEGIN
  SELECT id INTO admin_uid
  FROM auth.users
  WHERE lower(email) = lower(admin_email)
  LIMIT 1;

  IF admin_uid IS NULL THEN
    RAISE EXCEPTION 'No Supabase Auth user found for email: %', admin_email;
  END IF;

  INSERT INTO public.speaker_feedback_admins (user_id)
  VALUES (admin_uid)
  ON CONFLICT (user_id) DO NOTHING;

  RAISE NOTICE 'Manager privilege granted to %', admin_email;
END $$;
