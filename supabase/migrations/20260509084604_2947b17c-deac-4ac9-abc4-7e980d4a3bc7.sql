
CREATE OR REPLACE FUNCTION public.auto_advance_booking_on_member_response()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pending_count INT;
  v_rejected_count INT;
  v_current_status TEXT;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  SELECT status INTO v_current_status FROM public.bookings WHERE id = NEW.booking_id;

  -- Only act while booking is awaiting member responses
  IF v_current_status <> 'pending_members' THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'rejected' THEN
    UPDATE public.bookings
    SET status = 'cancelled'
    WHERE id = NEW.booking_id;
    RETURN NEW;
  END IF;

  IF NEW.status = 'accepted' THEN
    SELECT
      COUNT(*) FILTER (WHERE status = 'pending'),
      COUNT(*) FILTER (WHERE status = 'rejected')
    INTO v_pending_count, v_rejected_count
    FROM public.booking_members
    WHERE booking_id = NEW.booking_id;

    IF v_pending_count = 0 AND v_rejected_count = 0 THEN
      UPDATE public.bookings
      SET status = 'pending_admin'
      WHERE id = NEW.booking_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_advance_booking_on_member_response ON public.booking_members;
CREATE TRIGGER auto_advance_booking_on_member_response
AFTER UPDATE ON public.booking_members
FOR EACH ROW
EXECUTE FUNCTION public.auto_advance_booking_on_member_response();

-- Backfill: any booking still 'pending_members' where all members are accepted → pending_admin
UPDATE public.bookings b
SET status = 'pending_admin'
WHERE b.status = 'pending_members'
  AND EXISTS (SELECT 1 FROM public.booking_members m WHERE m.booking_id = b.id)
  AND NOT EXISTS (
    SELECT 1 FROM public.booking_members m
    WHERE m.booking_id = b.id AND m.status <> 'accepted'
  );
