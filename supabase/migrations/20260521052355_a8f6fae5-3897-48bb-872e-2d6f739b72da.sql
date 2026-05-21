
-- 1. Lock helper RPCs to authenticated users only (no anon/public exec)
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_blocked_slot(uuid, date, time, time) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_user_time_overlap(uuid, date, time, time, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_daily_hours(uuid, date, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.shares_booking(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_actor_email(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_send_email_secret() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_user_by_email(text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_unapproved_past_bookings() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.send_booking_reminders() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_blocked_slot(uuid, date, time, time) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_user_time_overlap(uuid, date, time, time, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_daily_hours(uuid, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shares_booking(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_actor_email(uuid) TO authenticated;

-- 2. Force bookings.user_id = auth.uid() on insert; block status escalation on update
CREATE OR REPLACE FUNCTION public.enforce_booking_owner()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_booking_owner ON public.bookings;
CREATE TRIGGER trg_enforce_booking_owner
BEFORE INSERT ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.enforce_booking_owner();

CREATE OR REPLACE FUNCTION public.prevent_status_escalation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF public.has_role(auth.uid(), 'admin') THEN RETURN NEW; END IF;
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('approved','rejected') THEN
    RAISE EXCEPTION 'Only admins can approve or reject bookings';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_prevent_status_escalation ON public.bookings;
CREATE TRIGGER trg_prevent_status_escalation
BEFORE UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.prevent_status_escalation();

-- 3. Force blocked_slots.created_by = auth.uid()
CREATE OR REPLACE FUNCTION public.enforce_blocked_slot_creator()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.created_by := auth.uid();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_blocked_slot_creator ON public.blocked_slots;
CREATE TRIGGER trg_enforce_blocked_slot_creator
BEFORE INSERT ON public.blocked_slots
FOR EACH ROW EXECUTE FUNCTION public.enforce_blocked_slot_creator();

-- 4. Atomic booking creation RPC
CREATE OR REPLACE FUNCTION public.create_booking_atomic(
  p_room_id uuid,
  p_title text,
  p_date date,
  p_start_time time,
  p_end_time time,
  p_member_emails text[] DEFAULT ARRAY[]::text[]
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_booking_id uuid;
  v_status text;
  v_email text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  v_status := CASE WHEN coalesce(array_length(p_member_emails,1),0) > 0
                   THEN 'pending_members' ELSE 'pending_admin' END;

  INSERT INTO public.bookings (room_id, user_id, title, date, start_time, end_time, status)
  VALUES (p_room_id, v_uid, p_title, p_date, p_start_time, p_end_time, v_status)
  RETURNING id INTO v_booking_id;

  IF coalesce(array_length(p_member_emails,1),0) > 0 THEN
    FOREACH v_email IN ARRAY p_member_emails LOOP
      INSERT INTO public.booking_members (booking_id, email)
      VALUES (v_booking_id, lower(trim(v_email)));
    END LOOP;
  END IF;

  RETURN v_booking_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.create_booking_atomic(uuid, text, date, time, time, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_booking_atomic(uuid, text, date, time, time, text[]) TO authenticated;
