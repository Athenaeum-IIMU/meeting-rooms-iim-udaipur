-- Create an internal schema that PostgREST does not expose
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;

-- Recreate has_role inside the private schema
CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role
  )
$$;

-- Recreate shares_booking inside the private schema
CREATE OR REPLACE FUNCTION private.shares_booking(_viewer uuid, _target uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    JOIN public.profiles p ON LOWER(p.email) = LOWER(bm.email)
    WHERE b.user_id = _viewer AND p.user_id = _target
    UNION ALL
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    JOIN public.profiles p ON LOWER(p.email) = LOWER(bm.email)
    WHERE b.user_id = _target AND p.user_id = _viewer
  )
$$;

REVOKE EXECUTE ON FUNCTION private.has_role(uuid, public.app_role)   FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.shares_booking(uuid, uuid)        FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION private.has_role(uuid, public.app_role)   TO authenticated;
GRANT  EXECUTE ON FUNCTION private.shares_booking(uuid, uuid)        TO authenticated;

-- Recreate all policies that referenced public.has_role / public.shares_booking
-- to use the private-schema versions instead.

-- user_roles
DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles;
CREATE POLICY "Admins can view all roles" ON public.user_roles
  FOR SELECT TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles;
CREATE POLICY "Admins can insert roles" ON public.user_roles
  FOR INSERT TO authenticated
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
CREATE POLICY "Admins can update roles" ON public.user_roles
  FOR UPDATE TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
CREATE POLICY "Admins can delete roles" ON public.user_roles
  FOR DELETE TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

-- rooms
DROP POLICY IF EXISTS "Admins can manage rooms" ON public.rooms;
CREATE POLICY "Admins can manage rooms" ON public.rooms
  FOR ALL TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

-- bookings
DROP POLICY IF EXISTS "Admins can view all bookings" ON public.bookings;
CREATE POLICY "Admins can view all bookings" ON public.bookings
  FOR SELECT TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can update any booking" ON public.bookings;
CREATE POLICY "Admins can update any booking" ON public.bookings
  FOR UPDATE TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

-- booking_members
DROP POLICY IF EXISTS "Admins can view all members" ON public.booking_members;
CREATE POLICY "Admins can view all members" ON public.booking_members
  FOR SELECT TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Admins can manage all members" ON public.booking_members;
CREATE POLICY "Admins can manage all members" ON public.booking_members
  FOR ALL TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

-- blocked_slots
DROP POLICY IF EXISTS "Admins can manage blocked slots" ON public.blocked_slots;
CREATE POLICY "Admins can manage blocked slots" ON public.blocked_slots
  FOR ALL TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (private.has_role(auth.uid(), 'admin'::public.app_role));

-- audit_log
DROP POLICY IF EXISTS "Admins can view audit log" ON public.audit_log;
CREATE POLICY "Admins can view audit log" ON public.audit_log
  FOR SELECT TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

-- waitlist
DROP POLICY IF EXISTS "Admins view all waitlist" ON public.waitlist;
CREATE POLICY "Admins view all waitlist" ON public.waitlist
  FOR SELECT TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

-- profiles
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (private.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Users can view profiles of shared bookings" ON public.profiles;
CREATE POLICY "Users can view profiles of shared bookings" ON public.profiles
  FOR SELECT TO authenticated
  USING (private.shares_booking(auth.uid(), user_id));

-- Now revoke EXECUTE on the public copies from anything signed-in users use.
-- The internal SECURITY DEFINER trigger functions still call public.has_role
-- and continue to work because they run as the function owner (postgres).
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.shares_booking(uuid, uuid)        FROM PUBLIC, anon, authenticated;
