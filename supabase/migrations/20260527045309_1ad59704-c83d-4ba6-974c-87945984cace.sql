
-- Security definer helpers (bypass RLS to avoid policy recursion)
CREATE OR REPLACE FUNCTION public.is_booking_member(_booking_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.booking_members bm
    WHERE bm.booking_id = _booking_id
      AND (
        bm.user_id = _user_id
        OR lower(bm.email) = lower((SELECT email FROM public.profiles WHERE user_id = _user_id LIMIT 1))
      )
  )
$$;

CREATE OR REPLACE FUNCTION public.is_booking_owner(_booking_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookings b
    WHERE b.id = _booking_id AND b.user_id = _user_id
  )
$$;

REVOKE EXECUTE ON FUNCTION public.is_booking_member(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_booking_owner(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_booking_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_booking_owner(uuid, uuid) TO authenticated;

-- Replace recursive policy on bookings
DROP POLICY IF EXISTS "Members can view their bookings" ON public.bookings;
CREATE POLICY "Members can view their bookings"
ON public.bookings
FOR SELECT
TO authenticated
USING (public.is_booking_member(id, auth.uid()));

-- Replace recursive policy on booking_members
DROP POLICY IF EXISTS "Users can view members of their bookings" ON public.booking_members;
CREATE POLICY "Users can view members of their bookings"
ON public.booking_members
FOR SELECT
TO authenticated
USING (public.is_booking_owner(booking_id, auth.uid()));

DROP POLICY IF EXISTS "Booking owners can insert members" ON public.booking_members;
CREATE POLICY "Booking owners can insert members"
ON public.booking_members
FOR INSERT
TO authenticated
WITH CHECK (public.is_booking_owner(booking_id, auth.uid()));
