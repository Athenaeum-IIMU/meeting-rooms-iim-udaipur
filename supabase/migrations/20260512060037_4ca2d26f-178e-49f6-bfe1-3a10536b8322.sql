
-- 1. Rejection reason column
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- 2. Update daily-hours: include accepted memberships in addition to owned bookings
CREATE OR REPLACE FUNCTION public.get_user_daily_hours(p_user_id uuid, p_date date, p_exclude_booking_id uuid DEFAULT NULL::uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() AND NOT public.has_role(auth.uid(), 'admin') THEN
    RETURN INTERVAL '0 hours';
  END IF;

  RETURN COALESCE((
    SELECT SUM(b.end_time - b.start_time)
    FROM public.bookings b
    WHERE b.date = p_date
      AND b.status IN ('approved', 'pending_admin', 'pending_members')
      AND (p_exclude_booking_id IS NULL OR b.id != p_exclude_booking_id)
      AND (
        b.user_id = p_user_id
        OR EXISTS (
          SELECT 1 FROM public.booking_members bm
          WHERE bm.booking_id = b.id
            AND bm.user_id = p_user_id
            AND bm.status = 'accepted'
        )
      )
  ), INTERVAL '0 hours');
END;
$function$;

-- 3. Booking-member validation: prevent invites/acceptances that conflict or exceed 4h
CREATE OR REPLACE FUNCTION public.validate_booking_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_booking RECORD;
  v_user_id UUID;
  v_overlap INT;
  v_total_min INT;
  v_new_min INT;
  v_should_validate BOOLEAN := false;
BEGIN
  SELECT id, user_id, date, start_time, end_time, status
  INTO v_booking FROM public.bookings WHERE id = NEW.booking_id;

  -- Skip if booking itself isn't active
  IF v_booking.status IN ('cancelled', 'rejected') THEN RETURN NEW; END IF;

  -- Resolve user (NEW.user_id may not be set yet on INSERT)
  v_user_id := NEW.user_id;
  IF v_user_id IS NULL THEN
    SELECT user_id INTO v_user_id FROM public.profiles WHERE LOWER(email) = LOWER(NEW.email) LIMIT 1;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  -- Validate on: INSERT (new invite) or UPDATE → accepted
  IF TG_OP = 'INSERT' THEN
    v_should_validate := true;
  ELSIF TG_OP = 'UPDATE' AND NEW.status = 'accepted' AND OLD.status <> 'accepted' THEN
    v_should_validate := true;
  END IF;
  IF NOT v_should_validate THEN RETURN NEW; END IF;

  -- Time overlap (across all rooms, owner or accepted member)
  SELECT count(*) INTO v_overlap
  FROM public.bookings b
  WHERE b.date = v_booking.date
    AND b.id <> v_booking.id
    AND b.status NOT IN ('cancelled', 'rejected')
    AND b.start_time < v_booking.end_time
    AND b.end_time > v_booking.start_time
    AND (
      b.user_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM public.booking_members bm2
        WHERE bm2.booking_id = b.id
          AND bm2.user_id = v_user_id
          AND bm2.status = 'accepted'
      )
    );
  IF v_overlap > 0 THEN
    RAISE EXCEPTION '% already has another meeting that overlaps this time', NEW.email;
  END IF;

  -- Combined 4-hour daily limit
  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (b.end_time - b.start_time))/60), 0)::int INTO v_total_min
  FROM public.bookings b
  WHERE b.date = v_booking.date
    AND b.id <> v_booking.id
    AND b.status NOT IN ('cancelled', 'rejected')
    AND (
      b.user_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM public.booking_members bm2
        WHERE bm2.booking_id = b.id
          AND bm2.user_id = v_user_id
          AND bm2.status = 'accepted'
      )
    );
  v_new_min := (EXTRACT(EPOCH FROM (v_booking.end_time - v_booking.start_time))/60)::int;
  IF v_total_min + v_new_min > 240 THEN
    RAISE EXCEPTION '% has reached the 4-hour daily booking limit', NEW.email;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS validate_booking_member_trigger ON public.booking_members;
CREATE TRIGGER validate_booking_member_trigger
BEFORE INSERT OR UPDATE ON public.booking_members
FOR EACH ROW EXECUTE FUNCTION public.validate_booking_member();

-- 4. Include rejection_reason in status-change notifications
CREATE OR REPLACE FUNCTION public.handle_booking_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_room_name TEXT;
  v_title TEXT;
  v_body TEXT;
  v_member RECORD;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('approved', 'rejected', 'cancelled') THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = NEW.room_id;

  v_title := CASE NEW.status
    WHEN 'approved' THEN 'Booking approved ✓'
    WHEN 'rejected' THEN 'Booking rejected'
    WHEN 'cancelled' THEN 'Booking cancelled'
  END;

  v_body := '"' || NEW.title || '" — ' || COALESCE(v_room_name, 'room') ||
            ' on ' || NEW.date || ' at ' ||
            to_char(NEW.start_time, 'HH24:MI') || '–' ||
            to_char(NEW.end_time, 'HH24:MI');

  IF NEW.status = 'rejected' AND NEW.rejection_reason IS NOT NULL AND NEW.rejection_reason <> '' THEN
    v_body := v_body || E'\nReason: ' || NEW.rejection_reason;
  END IF;

  INSERT INTO public.notifications (user_id, type, title, body, booking_id)
  VALUES (NEW.user_id, 'booking_' || NEW.status, v_title, v_body, NEW.id);

  FOR v_member IN
    SELECT email FROM public.booking_members
    WHERE booking_id = NEW.id AND status = 'accepted'
  LOOP
    PERFORM public.notify_user_by_email(
      v_member.email,
      'booking_' || NEW.status,
      v_title,
      v_body,
      NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

-- 5. Cleanup helper for past unapproved bookings
CREATE OR REPLACE FUNCTION public.cleanup_unapproved_past_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.booking_members
  WHERE booking_id IN (
    SELECT id FROM public.bookings
    WHERE date < CURRENT_DATE AND status <> 'approved'
  );
  DELETE FROM public.notifications
  WHERE booking_id IN (
    SELECT id FROM public.bookings
    WHERE date < CURRENT_DATE AND status <> 'approved'
  );
  DELETE FROM public.bookings
  WHERE date < CURRENT_DATE AND status <> 'approved';
END;
$function$;

GRANT EXECUTE ON FUNCTION public.cleanup_unapproved_past_bookings() TO authenticated;

-- 6. One-time wipe of all existing bookings
DELETE FROM public.notifications WHERE booking_id IS NOT NULL;
DELETE FROM public.booking_members;
DELETE FROM public.bookings;
