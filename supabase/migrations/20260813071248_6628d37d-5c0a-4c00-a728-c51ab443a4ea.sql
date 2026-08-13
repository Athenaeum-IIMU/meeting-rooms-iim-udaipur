-- 1. Fix conflict notification insert (notifications has no "data"/"message" column)
CREATE OR REPLACE FUNCTION public.auto_approve_on_pending_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conflict_count INT;
  v_blocked_count INT;
BEGIN
  IF NEW.status <> 'pending_admin' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'pending_admin' THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO v_conflict_count
  FROM public.bookings b
  WHERE b.room_id = NEW.room_id
    AND b.date = NEW.date
    AND b.status = 'approved'
    AND b.id <> NEW.id
    AND b.start_time < NEW.end_time
    AND b.end_time > NEW.start_time;

  SELECT COUNT(*) INTO v_blocked_count
  FROM public.blocked_slots bs
  WHERE bs.room_id = NEW.room_id
    AND bs.date = NEW.date
    AND bs.start_time < NEW.end_time
    AND bs.end_time > NEW.start_time;

  IF v_conflict_count = 0 AND v_blocked_count = 0 THEN
    NEW.status := 'approved';
  ELSE
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    SELECT ur.user_id, 'admin_conflict',
           'Booking needs review: conflict',
           'Booking "' || COALESCE(NEW.title, '(untitled)') || '" is awaiting admin approval — a clash was detected.',
           NEW.id
    FROM public.user_roles ur
    WHERE ur.role = 'admin';
  END IF;

  RETURN NEW;
END;
$$;

-- 2. Shared re-evaluation routine: approve any pending_admin booking whose slot is now free
CREATE OR REPLACE FUNCTION public.reevaluate_pending_admin(p_room_id uuid, p_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
BEGIN
  FOR b IN
    SELECT * FROM public.bookings
    WHERE status = 'pending_admin'
      AND room_id = p_room_id
      AND date = p_date
      AND (date + end_time) AT TIME ZONE 'Asia/Kolkata' > now()
    ORDER BY COALESCE(pending_admin_since, created_at) ASC
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.bookings x
      WHERE x.room_id = b.room_id AND x.date = b.date AND x.id <> b.id
        AND x.status = 'approved'
        AND x.start_time < b.end_time AND x.end_time > b.start_time
    ) AND NOT EXISTS (
      SELECT 1 FROM public.blocked_slots bs
      WHERE bs.room_id = b.room_id AND bs.date = b.date
        AND bs.start_time < b.end_time AND bs.end_time > b.start_time
    ) THEN
      UPDATE public.bookings SET status = 'approved' WHERE id = b.id AND status = 'pending_admin';
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.reevaluate_pending_admin(uuid, date) FROM PUBLIC, anon, authenticated;

-- 3. Fixed background job: correct date + Asia/Kolkata time handling
CREATE OR REPLACE FUNCTION public.auto_approve_imminent_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
  has_conflict boolean;
BEGIN
  FOR b IN
    SELECT * FROM public.bookings
    WHERE status = 'pending_admin'
      AND COALESCE(pending_admin_since, created_at) <= now() - interval '1 minute'
      AND (date + end_time) AT TIME ZONE 'Asia/Kolkata' > now()
    ORDER BY date ASC, start_time ASC
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM public.bookings x
      WHERE x.room_id = b.room_id AND x.date = b.date AND x.id <> b.id
        AND x.status = 'approved'
        AND x.start_time < b.end_time AND x.end_time > b.start_time
    ) OR EXISTS (
      SELECT 1 FROM public.blocked_slots bs
      WHERE bs.room_id = b.room_id AND bs.date = b.date
        AND bs.start_time < b.end_time AND bs.end_time > b.start_time
    ) INTO has_conflict;

    IF NOT has_conflict THEN
      UPDATE public.bookings SET status = 'approved' WHERE id = b.id AND status = 'pending_admin';
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.auto_approve_imminent_bookings() FROM PUBLIC, anon, authenticated;

-- 4. Re-check pending bookings when a slot is freed
CREATE OR REPLACE FUNCTION public.trg_reevaluate_on_slot_freed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'blocked_slots' THEN
    PERFORM public.reevaluate_pending_admin(OLD.room_id, OLD.date);
    RETURN OLD;
  END IF;

  IF OLD.status = 'approved' AND NEW.status IN ('cancelled', 'rejected') THEN
    PERFORM public.reevaluate_pending_admin(NEW.room_id, NEW.date);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reevaluate_on_booking_freed ON public.bookings;
CREATE TRIGGER trg_reevaluate_on_booking_freed
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.trg_reevaluate_on_slot_freed();

DROP TRIGGER IF EXISTS trg_reevaluate_on_block_removed ON public.blocked_slots;
CREATE TRIGGER trg_reevaluate_on_block_removed
AFTER DELETE ON public.blocked_slots
FOR EACH ROW EXECUTE FUNCTION public.trg_reevaluate_on_slot_freed();
