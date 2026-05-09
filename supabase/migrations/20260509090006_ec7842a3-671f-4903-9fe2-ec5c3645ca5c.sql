-- Hard-enforce per-user cross-room rules at the database level
CREATE OR REPLACE FUNCTION public.enforce_user_booking_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overlap BOOLEAN;
  v_total_minutes INT;
  v_new_minutes INT;
  v_user_emails TEXT[];
BEGIN
  -- Skip enforcement on status-only / non-scheduling updates
  IF TG_OP = 'UPDATE'
     AND NEW.user_id = OLD.user_id
     AND NEW.date = OLD.date
     AND NEW.start_time = OLD.start_time
     AND NEW.end_time = OLD.end_time
     AND NEW.room_id = OLD.room_id THEN
    RETURN NEW;
  END IF;

  -- Skip when the new row isn't in an "active" state
  IF NEW.status NOT IN ('approved', 'pending_admin', 'pending_members') THEN
    RETURN NEW;
  END IF;

  -- Collect emails for this user (for membership-based overlap)
  SELECT ARRAY_AGG(LOWER(email)) INTO v_user_emails
  FROM public.profiles WHERE user_id = NEW.user_id;

  -- 1. Cross-room overlap check: same user as owner OR as accepted/pending member
  SELECT EXISTS (
    SELECT 1 FROM public.bookings b
    WHERE b.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND b.date = NEW.date
      AND b.status IN ('approved', 'pending_admin', 'pending_members')
      AND b.start_time < NEW.end_time
      AND b.end_time > NEW.start_time
      AND (
        b.user_id = NEW.user_id
        OR EXISTS (
          SELECT 1 FROM public.booking_members bm
          WHERE bm.booking_id = b.id
            AND bm.status <> 'rejected'
            AND LOWER(bm.email) = ANY(COALESCE(v_user_emails, ARRAY[]::TEXT[]))
        )
      )
  ) INTO v_overlap;

  IF v_overlap THEN
    RAISE EXCEPTION 'You already have another booking that overlaps with this time (across all rooms).'
      USING ERRCODE = 'check_violation';
  END IF;

  -- 2. Combined 4-hour daily limit across ALL rooms (owner bookings)
  SELECT COALESCE(EXTRACT(EPOCH FROM SUM(end_time - start_time))/60, 0)::INT
  INTO v_total_minutes
  FROM public.bookings
  WHERE user_id = NEW.user_id
    AND date = NEW.date
    AND status IN ('approved', 'pending_admin', 'pending_members')
    AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

  v_new_minutes := EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))/60;

  IF v_total_minutes + v_new_minutes > 240 THEN
    RAISE EXCEPTION 'This would exceed the 4-hour combined daily limit across all rooms (current: % min, adding: % min).',
      v_total_minutes, v_new_minutes
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_user_booking_rules_trigger ON public.bookings;
CREATE TRIGGER enforce_user_booking_rules_trigger
  BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_user_booking_rules();