
-- 1. Backfill user_id on existing booking_members where profile now exists
UPDATE public.booking_members bm
SET user_id = p.user_id
FROM public.profiles p
WHERE bm.user_id IS NULL
  AND LOWER(p.email) = LOWER(bm.email);

-- 2. Update handle_new_user to backfill booking_members for this email
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (user_id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');

  -- Link any pre-existing booking_members invites to this new user
  UPDATE public.booking_members
  SET user_id = NEW.id
  WHERE user_id IS NULL
    AND LOWER(email) = LOWER(NEW.email);

  RETURN NEW;
END;
$function$;
