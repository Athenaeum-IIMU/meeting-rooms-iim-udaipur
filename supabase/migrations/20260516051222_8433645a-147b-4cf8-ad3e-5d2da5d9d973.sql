
-- Replace the booking owner update RLS policy to allow editing while in 'needs_replacement'
DROP POLICY IF EXISTS "Users can update own bookings" ON public.bookings;
CREATE POLICY "Users can update own bookings"
ON public.bookings
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (
  auth.uid() = user_id
  AND status = ANY (ARRAY['pending_members'::text, 'pending_admin'::text, 'cancelled'::text, 'needs_replacement'::text])
);

-- New advance logic: handle decline by checking room min_members
CREATE OR REPLACE FUNCTION public.auto_advance_booking_on_member_response()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_booking RECORD;
  v_min_members INT;
  v_accepted INT;
  v_pending INT;
  v_max_possible INT;
  v_committed INT;
  v_new_status TEXT;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  SELECT b.id, b.status, b.user_id, b.room_id, r.min_members
  INTO v_booking
  FROM public.bookings b
  LEFT JOIN public.rooms r ON r.id = b.room_id
  WHERE b.id = NEW.booking_id;

  IF v_booking.status NOT IN ('pending_members', 'needs_replacement') THEN
    RETURN NEW;
  END IF;

  v_min_members := COALESCE(v_booking.min_members, 3);

  SELECT
    COUNT(*) FILTER (WHERE status = 'accepted'),
    COUNT(*) FILTER (WHERE status = 'pending')
  INTO v_accepted, v_pending
  FROM public.booking_members
  WHERE booking_id = NEW.booking_id;

  v_committed    := v_accepted + 1;             -- include organizer
  v_max_possible := v_accepted + v_pending + 1; -- best-case if all pending accept

  IF v_max_possible < v_min_members THEN
    -- Not enough people possible → ask organizer to fix
    v_new_status := 'needs_replacement';
  ELSIF v_pending = 0 THEN
    -- Everyone has responded; we already know v_committed >= min
    v_new_status := 'pending_admin';
  ELSE
    -- Still waiting on some pending responses; could still reach minimum
    v_new_status := 'pending_members';
  END IF;

  IF v_new_status <> v_booking.status THEN
    UPDATE public.bookings SET status = v_new_status WHERE id = NEW.booking_id;
  END IF;

  RETURN NEW;
END;
$function$;

-- Notify organizer when their booking falls into 'needs_replacement'
CREATE OR REPLACE FUNCTION public.notify_needs_replacement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_room_name TEXT;
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status <> 'needs_replacement' THEN RETURN NEW; END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = NEW.room_id;

  INSERT INTO public.notifications (user_id, type, title, body, booking_id)
  VALUES (
    NEW.user_id,
    'needs_replacement',
    'Action needed: add replacement members',
    'Members declined your meeting "' || NEW.title || '" in ' ||
    COALESCE(v_room_name, 'room') || ' on ' || NEW.date ||
    ' at ' || to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') ||
    '. Please add replacement members or cancel. The booking will auto-cancel 30 minutes before start.',
    NEW.id
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_needs_replacement ON public.bookings;
CREATE TRIGGER trg_notify_needs_replacement
AFTER UPDATE ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.notify_needs_replacement();

-- Extend cleanup to also auto-cancel needs_replacement within 30 min of start
CREATE OR REPLACE FUNCTION public.cleanup_unapproved_past_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Auto-cancel needs_replacement bookings whose start is within 30 minutes
  UPDATE public.bookings
  SET status = 'cancelled',
      rejection_reason = COALESCE(rejection_reason, 'Auto-cancelled: not enough members confirmed within 30 minutes of start')
  WHERE status = 'needs_replacement'
    AND ((date::text || ' ' || start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata')
        <= now() + INTERVAL '30 minutes';

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
