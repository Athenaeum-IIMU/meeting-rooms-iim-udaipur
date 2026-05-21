
-- 1) Fix public.shares_booking: join on user_id, restrict to confirmed members + active bookings
CREATE OR REPLACE FUNCTION public.shares_booking(_viewer uuid, _target uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    WHERE b.user_id = _viewer
      AND bm.user_id = _target
      AND bm.user_id IS NOT NULL
      AND bm.status = 'accepted'
      AND b.status IN ('approved','pending_admin','pending_members','needs_replacement')
      AND b.date >= CURRENT_DATE
    UNION ALL
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    WHERE b.user_id = _target
      AND bm.user_id = _viewer
      AND bm.user_id IS NOT NULL
      AND bm.status = 'accepted'
      AND b.status IN ('approved','pending_admin','pending_members','needs_replacement')
      AND b.date >= CURRENT_DATE
  )
$$;

-- 2) Revoke EXECUTE on SECURITY DEFINER helper functions from anon/public/authenticated.
-- These are used internally by triggers/policies (which run as definer) and don't need direct API exposure.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.proname IN (
        'has_role','shares_booking','get_actor_email','get_send_email_secret',
        'notify_user_by_email','cleanup_unapproved_past_bookings','send_booking_reminders',
        'check_user_time_overlap','get_user_daily_hours'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC, anon, authenticated',
                   r.nspname, r.proname, r.args);
  END LOOP;
END $$;

-- check_booking_conflict and check_blocked_slot are STABLE non-SECURITY DEFINER (or okay to expose),
-- but revoke from anon to keep them auth-only.
REVOKE ALL ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.check_blocked_slot(uuid, date, time, time) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_blocked_slot(uuid, date, time, time) TO authenticated;

-- create_booking_atomic should remain callable by authenticated users
GRANT EXECUTE ON FUNCTION public.create_booking_atomic(uuid, text, date, time, time, text[]) TO authenticated;

-- 3) Defense-in-depth: prevent any non-admin from inserting/updating/deleting user_roles
-- (existing policies already enforce admin-only writes; add explicit USING on UPDATE/DELETE has been done.
--  Add an extra trigger-level guard so even a misconfigured policy can't allow self-escalation.)
CREATE OR REPLACE FUNCTION public.prevent_role_self_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);  -- service role / system
  END IF;
  IF NOT private.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Only admins can modify user roles';
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS user_roles_admin_only ON public.user_roles;
CREATE TRIGGER user_roles_admin_only
BEFORE INSERT OR UPDATE OR DELETE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.prevent_role_self_escalation();
