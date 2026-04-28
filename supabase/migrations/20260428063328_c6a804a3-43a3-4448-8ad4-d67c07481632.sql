
-- 1. Fix booking status escalation: restrict owner updates
DROP POLICY IF EXISTS "Users can update own bookings" ON public.bookings;
CREATE POLICY "Users can update own bookings" ON public.bookings
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND status IN ('pending_members', 'pending_admin', 'cancelled')
  );

-- 2. Prevent self-escalation on user_roles: explicit INSERT/UPDATE/DELETE admin-only
DROP POLICY IF EXISTS "Admins can manage roles" ON public.user_roles;
CREATE POLICY "Admins can insert roles" ON public.user_roles
  FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can update roles" ON public.user_roles
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Admins can delete roles" ON public.user_roles
  FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role));

-- 3. Restrict profile email/name exposure
-- Helper: do viewer and target share a booking (as owner/member)?
CREATE OR REPLACE FUNCTION public.shares_booking(_viewer uuid, _target uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    -- viewer owns a booking where target is a member
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    JOIN public.profiles p ON LOWER(p.email) = LOWER(bm.email)
    WHERE b.user_id = _viewer AND p.user_id = _target
    UNION ALL
    -- target owns a booking where viewer is a member
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    JOIN public.profiles p ON LOWER(p.email) = LOWER(bm.email)
    WHERE b.user_id = _target AND p.user_id = _viewer
  )
$$;

DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "Users can view profiles of shared bookings" ON public.profiles
  FOR SELECT TO authenticated
  USING (public.shares_booking(auth.uid(), user_id));

-- 4. Revoke EXECUTE from notify_user_by_email (internal use only via triggers)
REVOKE EXECUTE ON FUNCTION public.notify_user_by_email(text, text, text, text, uuid)
  FROM PUBLIC, anon, authenticated;

-- 5. Revoke EXECUTE from other internal SECURITY DEFINER helpers not meant for direct client calls
REVOKE EXECUTE ON FUNCTION public.get_actor_email(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.send_booking_reminders() FROM PUBLIC, anon, authenticated;

-- Keep EXECUTE on these (used by client for pre-flight checks):
-- has_role, check_booking_conflict, check_user_time_overlap, check_blocked_slot,
-- get_user_daily_hours, shares_booking

-- 6. Realtime channel authorization: restrict realtime.messages so users can only
-- subscribe to their own topics (e.g., notifications:<their uid>)
ALTER TABLE IF EXISTS realtime.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only subscribe to their own topics" ON realtime.messages;
CREATE POLICY "Users can only subscribe to their own topics" ON realtime.messages
  FOR SELECT TO authenticated
  USING (
    -- allow topics that end with the user's own uid or are explicitly public
    (realtime.topic() LIKE '%:' || auth.uid()::text)
    OR (realtime.topic() LIKE 'public:%')
  );
