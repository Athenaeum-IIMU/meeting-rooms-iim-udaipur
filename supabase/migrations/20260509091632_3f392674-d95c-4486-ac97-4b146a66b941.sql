
-- 1. Allow handle_new_user to link pending invites without tripping the tamper guard.
CREATE OR REPLACE FUNCTION public.prevent_booking_member_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admins bypass
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  -- Allow system-level linking of an invite to a newly created user
  -- (auth.uid() is NULL inside the auth signup trigger, and this only
  -- promotes a NULL user_id to a real one — never reassigns).
  IF auth.uid() IS NULL AND OLD.user_id IS NULL AND NEW.user_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.booking_id IS DISTINCT FROM OLD.booking_id THEN
    RAISE EXCEPTION 'Cannot change booking_id of a membership';
  END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'Cannot change user_id of a membership';
  END IF;
  IF LOWER(NEW.email) IS DISTINCT FROM LOWER(OLD.email) THEN
    RAISE EXCEPTION 'Cannot change email of a membership';
  END IF;

  RETURN NEW;
END;
$$;

-- 2. Reject bookings in the past (server-side hard guard).
CREATE OR REPLACE FUNCTION public.enforce_user_booking_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overlap_count int;
  v_total_minutes int;
  v_new_minutes int;
  v_start_ts timestamptz;
BEGIN
  -- Block past bookings (Asia/Kolkata local time at IIM Udaipur).
  v_start_ts := (NEW.date::text || ' ' || NEW.start_time::text)::timestamp
                AT TIME ZONE 'Asia/Kolkata';
  IF v_start_ts < now() THEN
    RAISE EXCEPTION 'Cannot create or modify a booking that starts in the past';
  END IF;

  -- Cross-room overlap check: same user as owner OR accepted/pending member
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

  -- Combined 4-hour daily limit across all rooms
  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (b.end_time - b.start_time)) / 60), 0)::int
  INTO v_total_minutes
  FROM public.bookings b
  WHERE b.date = NEW.date
    AND b.id <> NEW.id
    AND b.status <> 'cancelled'
    AND b.user_id = NEW.user_id;

  v_new_minutes := (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60)::int;

  IF v_total_minutes + v_new_minutes > 240 THEN
    RAISE EXCEPTION 'Daily booking limit of 4 hours exceeded';
  END IF;

  RETURN NEW;
END;
$$;
