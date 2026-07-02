-- Allow status transitions to cancelled/rejected without re-validating past time
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
  -- Skip all checks if we're just cancelling/rejecting
  IF TG_OP = 'UPDATE' AND NEW.status IN ('cancelled','rejected')
     AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    RETURN NEW;
  END IF;

  v_start_ts := (NEW.date::text || ' ' || NEW.start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata';
  IF v_start_ts < now() THEN
    RAISE EXCEPTION 'Cannot create or modify a booking that starts in the past';
  END IF;

  v_new_minutes := (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60)::int;
  IF v_new_minutes < 30 THEN RAISE EXCEPTION 'A booking must be at least 30 minutes long'; END IF;
  IF v_new_minutes > 120 THEN RAISE EXCEPTION 'A single booking cannot be longer than 2 hours'; END IF;

  SELECT count(*) INTO v_overlap_count
  FROM public.bookings b
  WHERE b.date = NEW.date AND b.id <> NEW.id AND b.status <> 'cancelled'
    AND b.start_time < NEW.end_time AND b.end_time > NEW.start_time
    AND (b.user_id = NEW.user_id
      OR EXISTS (SELECT 1 FROM public.booking_members bm
        WHERE bm.booking_id = b.id AND bm.user_id = NEW.user_id
          AND bm.status IN ('pending','accepted')));
  IF v_overlap_count > 0 THEN RAISE EXCEPTION 'You already have a booking that overlaps this time'; END IF;

  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (b.end_time - b.start_time)) / 60), 0)::int
  INTO v_total_minutes
  FROM public.bookings b
  WHERE b.date = NEW.date AND b.id <> NEW.id AND b.status <> 'cancelled' AND b.user_id = NEW.user_id;
  IF v_total_minutes + v_new_minutes > 240 THEN
    RAISE EXCEPTION 'Daily booking limit of 4 hours exceeded';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE EXTENSION IF NOT EXISTS btree_gist;

UPDATE public.bookings
   SET status = 'rejected',
       rejection_reason = COALESCE(rejection_reason,'Duplicate submission (race condition) — kept earliest booking.')
 WHERE id = 'cbb0aacd-84c4-4c4c-8e03-e6dd4308a38a';

WITH ranked AS (
  SELECT id, room_id, date, start_time, end_time, created_at
  FROM public.bookings
  WHERE status IN ('approved','pending_admin','pending_members','needs_replacement')
),
dupes AS (
  SELECT a.id FROM ranked a JOIN ranked b
    ON a.room_id=b.room_id AND a.date=b.date AND a.id<>b.id
   AND a.start_time < b.end_time AND a.end_time > b.start_time
   AND a.created_at > b.created_at
)
UPDATE public.bookings SET status='rejected',
  rejection_reason = COALESCE(rejection_reason,'Duplicate submission (race condition) — kept earliest booking.')
 WHERE id IN (SELECT id FROM dupes);

ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_no_room_overlap;
ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_no_room_overlap
  EXCLUDE USING gist (
    room_id WITH =,
    date    WITH =,
    tsrange(('2000-01-01'::date + start_time)::timestamp,
            ('2000-01-01'::date + end_time)::timestamp, '[)') WITH &&
  )
  WHERE (status IN ('approved','pending_admin','pending_members','needs_replacement'));
