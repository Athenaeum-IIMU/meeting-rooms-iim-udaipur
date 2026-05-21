
CREATE OR REPLACE FUNCTION public.enforce_user_booking_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_overlap_count int;
  v_total_minutes int;
  v_new_minutes int;
  v_start_ts timestamptz;
BEGIN
  v_start_ts := (NEW.date::text || ' ' || NEW.start_time::text)::timestamp
                AT TIME ZONE 'Asia/Kolkata';
  IF v_start_ts < now() THEN
    RAISE EXCEPTION 'Cannot create or modify a booking that starts in the past';
  END IF;

  v_new_minutes := (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60)::int;

  IF v_new_minutes < 30 THEN
    RAISE EXCEPTION 'A booking must be at least 30 minutes long';
  END IF;

  IF v_new_minutes > 120 THEN
    RAISE EXCEPTION 'A single booking cannot be longer than 2 hours';
  END IF;

  SELECT count(*) INTO v_overlap_count
  FROM public.bookings b
  WHERE b.date = NEW.date
    AND b.id <> NEW.id
    AND b.status <> 'cancelled'
    AND b.start_time < NEW.end_time
    AND b.end_time > NEW.start_time
    AND (
      b.user_id = NEW.user_id
      OR EXISTS (
        SELECT 1 FROM public.booking_members bm
        WHERE bm.booking_id = b.id
          AND bm.user_id = NEW.user_id
          AND bm.status IN ('pending', 'accepted')
      )
    );
  IF v_overlap_count > 0 THEN
    RAISE EXCEPTION 'You already have a booking that overlaps this time';
  END IF;

  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (b.end_time - b.start_time)) / 60), 0)::int
  INTO v_total_minutes
  FROM public.bookings b
  WHERE b.date = NEW.date
    AND b.id <> NEW.id
    AND b.status <> 'cancelled'
    AND b.user_id = NEW.user_id;

  IF v_total_minutes + v_new_minutes > 240 THEN
    RAISE EXCEPTION 'Daily booking limit of 4 hours exceeded';
  END IF;

  RETURN NEW;
END;
$function$;
