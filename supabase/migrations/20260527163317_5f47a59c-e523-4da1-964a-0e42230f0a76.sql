
-- ============================================================
-- 1. BOOKINGS: remove the "approved bookings visible to all" leak
-- ============================================================
DROP POLICY IF EXISTS "Users can view approved bookings" ON public.bookings;

-- Replace with strict own-only SELECT (member access already exists separately)
CREATE POLICY "Users can view own bookings"
ON public.bookings
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Helper: anonymized busy-slot view callable by any authenticated user
-- Returns only room/date/time + minimal status, no title or owner info
CREATE OR REPLACE FUNCTION public.get_calendar_busy_slots(
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  id uuid,
  room_id uuid,
  date date,
  start_time time,
  end_time time,
  status text,
  is_mine boolean,
  title text,
  user_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.id,
    b.room_id,
    b.date,
    b.start_time,
    b.end_time,
    b.status,
    (b.user_id = auth.uid()) AS is_mine,
    CASE
      WHEN b.user_id = auth.uid() THEN b.title
      WHEN EXISTS (
        SELECT 1 FROM public.booking_members bm
        WHERE bm.booking_id = b.id AND bm.user_id = auth.uid()
      ) THEN b.title
      ELSE 'Busy'
    END AS title,
    CASE
      WHEN b.user_id = auth.uid() THEN b.user_id
      WHEN EXISTS (
        SELECT 1 FROM public.booking_members bm
        WHERE bm.booking_id = b.id AND bm.user_id = auth.uid()
      ) THEN b.user_id
      ELSE NULL
    END AS user_id
  FROM public.bookings b
  WHERE b.date BETWEEN p_start_date AND p_end_date
    AND b.status IN ('approved', 'pending_admin', 'pending_members', 'needs_replacement')
    AND auth.uid() IS NOT NULL;
$$;

REVOKE EXECUTE ON FUNCTION public.get_calendar_busy_slots(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_calendar_busy_slots(date, date) TO authenticated, service_role;

-- ============================================================
-- 2. PROFILES: hard-lock email column so booking_members email
--    inference attack cannot be staged.
-- ============================================================
CREATE OR REPLACE FUNCTION public.prevent_profile_email_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admins and system (no auth.uid) may set/sync email; regular users cannot change it.
  IF auth.uid() IS NULL OR private.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND LOWER(NEW.email) IS DISTINCT FROM LOWER(OLD.email) THEN
    RAISE EXCEPTION 'Email cannot be changed; it stays linked to your verified sign-in';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS prevent_profile_email_change_trg ON public.profiles;
CREATE TRIGGER prevent_profile_email_change_trg
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.prevent_profile_email_change();

-- ============================================================
-- 3. EMAIL_DELIVERY_LOG: explicit user SELECT + block all writes
-- ============================================================
CREATE POLICY "Users view own email log"
ON public.email_delivery_log
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Force RLS so SECURITY DEFINER functions writing must satisfy policies
-- (triggers still bypass via SECURITY DEFINER as table owner; this only locks app writes)
ALTER TABLE public.email_delivery_log FORCE ROW LEVEL SECURITY;

-- ============================================================
-- 4. REALTIME: scope channel topics
-- ============================================================
DO $$
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS "Authenticated can receive realtime" ON realtime.messages';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  EXECUTE $p$
    CREATE POLICY "Authenticated scoped realtime"
    ON realtime.messages
    FOR SELECT
    TO authenticated
    USING (
      realtime.topic() IN ('realtime-bookings')
      OR realtime.topic() = 'user:' || auth.uid()::text
      OR realtime.topic() LIKE 'public:%'
    )
  $p$;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ============================================================
-- 5. SECURITY DEFINER functions: revoke EXECUTE on internal helpers
-- ============================================================
DO $$
DECLARE
  fn_name text;
  internal_fns text[] := ARRAY[
    'public.handle_booking_member_response()',
    'public.validate_waitlist_entry()',
    'public.enforce_booking_owner()',
    'public.reset_booking_on_owner_edit()',
    'public.enforce_blocked_slot_creator()',
    'public.prevent_status_escalation()',
    'public.audit_slot_blocked()',
    'public.audit_slot_unblocked()',
    'public.prevent_role_self_escalation()',
    'public.audit_booking_status_change()',
    'public.handle_slot_blocked()',
    'public.notify_waitlist_on_freed()',
    'public.validate_booking_member()',
    'public.prevent_booking_member_tampering()',
    'public.send_booking_reminders()',
    'public.enforce_user_booking_rules()',
    'public.handle_booking_modified()',
    'public.get_actor_email(uuid)',
    'public.send_notification_email()',
    'public.prevent_user_admin_field_tampering()',
    'public.notify_user_by_email(text, text, text, text, uuid)',
    'public.validate_booking_date()',
    'public.get_send_email_secret()',
    'public.notify_needs_replacement()',
    'public.enforce_profile_email_matches_auth()',
    'public.enforce_iimu_email_domain()',
    'public.enforce_iimu_email_member()',
    'public.handle_booking_status_change()',
    'public.handle_new_user()',
    'public.audit_booking_modified()',
    'public.set_booking_member_user_id()',
    'public.audit_role_change()',
    'public.handle_booking_member_invite()',
    'public.auto_advance_booking_on_member_response()',
    'public.cleanup_unapproved_past_bookings()',
    'public.shares_booking(uuid, uuid)',
    'public.prevent_profile_email_change()'
  ];
BEGIN
  FOREACH fn_name IN ARRAY internal_fns LOOP
    BEGIN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn_name);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipped revoke for %: %', fn_name, SQLERRM;
    END;
  END LOOP;
END $$;

-- Re-affirm grants on user-callable helpers
GRANT EXECUTE ON FUNCTION public.is_current_user_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_booking_atomic(uuid, text, date, time, time, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_booking_invite_atomic(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_user_time_overlap(uuid, date, time, time, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_daily_hours(uuid, date, uuid) TO authenticated;
