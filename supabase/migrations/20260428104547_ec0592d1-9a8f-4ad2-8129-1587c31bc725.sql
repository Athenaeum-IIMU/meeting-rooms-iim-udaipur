-- 1) Lock down SECURITY DEFINER helpers and downgrade safe ones to INVOKER

-- Convert pure read-only helpers to SECURITY INVOKER (they only read RLS-public tables)
ALTER FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) SECURITY INVOKER;
ALTER FUNCTION public.check_blocked_slot(uuid, date, time, time) SECURITY INVOKER;

-- Revoke broad EXECUTE and grant only to authenticated for the remaining definer helpers
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.shares_booking(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_user_time_overlap(uuid, date, time, time, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_daily_hours(uuid, date, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_blocked_slot(uuid, date, time, time) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shares_booking(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_user_time_overlap(uuid, date, time, time, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_daily_hours(uuid, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_blocked_slot(uuid, date, time, time) TO authenticated;

-- 2) Eliminate booking_members email-impersonation vector

-- 2a) Enforce case-insensitive unique emails on profiles
-- Backfill: if duplicates exist (shouldn't, but be safe), the index creation will surface it.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_email_lower_unique
  ON public.profiles (LOWER(email));

-- 2b) Backfill booking_members.user_id from profiles by email
UPDATE public.booking_members bm
SET user_id = p.user_id
FROM public.profiles p
WHERE bm.user_id IS NULL
  AND LOWER(p.email) = LOWER(bm.email);

-- 2c) Trigger to always set user_id on insert/update from profiles
CREATE OR REPLACE FUNCTION public.set_booking_member_user_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  SELECT user_id INTO NEW.user_id
  FROM public.profiles
  WHERE LOWER(email) = LOWER(NEW.email)
  LIMIT 1;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_booking_member_user_id() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_set_booking_member_user_id ON public.booking_members;
CREATE TRIGGER trg_set_booking_member_user_id
BEFORE INSERT OR UPDATE OF email ON public.booking_members
FOR EACH ROW EXECUTE FUNCTION public.set_booking_member_user_id();

-- 2d) Tighten "Members can update own status" — match by user_id, not email
DROP POLICY IF EXISTS "Members can update own status" ON public.booking_members;
CREATE POLICY "Members can update own status"
ON public.booking_members
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 2e) Also tighten "Users can view their own memberships" the same way
DROP POLICY IF EXISTS "Users can view their own memberships" ON public.booking_members;
CREATE POLICY "Users can view their own memberships"
ON public.booking_members
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- 3) Prevent users from changing their profile email to someone else's identity
-- (Hardens 2a by ensuring users can only set email to their auth.users email)
CREATE OR REPLACE FUNCTION public.enforce_profile_email_matches_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_email TEXT;
BEGIN
  -- Only enforce when email is changing
  IF TG_OP = 'UPDATE' AND NEW.email = OLD.email THEN
    RETURN NEW;
  END IF;

  SELECT email INTO v_auth_email FROM auth.users WHERE id = NEW.user_id;

  IF v_auth_email IS NULL OR LOWER(v_auth_email) <> LOWER(NEW.email) THEN
    RAISE EXCEPTION 'Profile email must match your verified auth email';
  END IF;

  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.enforce_profile_email_matches_auth() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enforce_profile_email ON public.profiles;
CREATE TRIGGER trg_enforce_profile_email
BEFORE INSERT OR UPDATE OF email ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_profile_email_matches_auth();