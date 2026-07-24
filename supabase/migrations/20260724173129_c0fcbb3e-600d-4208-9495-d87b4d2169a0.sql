
CREATE OR REPLACE FUNCTION public.auto_approve_on_pending_admin()
RETURNS TRIGGER
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
    INSERT INTO public.notifications (user_id, type, title, body, data)
    SELECT ur.user_id, 'admin_conflict',
           'Booking needs review: conflict',
           'Booking "' || NEW.title || '" awaiting admin — conflicts detected.',
           jsonb_build_object('booking_id', NEW.id)
    FROM public.user_roles ur
    WHERE ur.role = 'admin';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_approve_on_pending_admin ON public.bookings;
CREATE TRIGGER trg_auto_approve_on_pending_admin
BEFORE INSERT OR UPDATE OF status ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.auto_approve_on_pending_admin();

-- Approve currently waiting bookings, bypassing user-side guards
SET session_replication_role = replica;
UPDATE public.bookings b
SET status = 'approved'
WHERE b.status = 'pending_admin'
  AND NOT EXISTS (
    SELECT 1 FROM public.bookings b2
    WHERE b2.room_id = b.room_id AND b2.date = b.date
      AND b2.status = 'approved' AND b2.id <> b.id
      AND b2.start_time < b.end_time AND b2.end_time > b.start_time
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.blocked_slots bs
    WHERE bs.room_id = b.room_id AND bs.date = b.date
      AND bs.start_time < b.end_time AND bs.end_time > b.start_time
  );
SET session_replication_role = origin;
