-- Track reminders to avoid duplicates
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN NOT NULL DEFAULT false;

-- Function: send 15-minute reminders
CREATE OR REPLACE FUNCTION public.send_booking_reminders()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking RECORD;
  v_room TEXT;
  v_member RECORD;
  v_body TEXT;
BEGIN
  FOR v_booking IN
    SELECT b.id, b.user_id, b.title, b.room_id, b.date, b.start_time, b.end_time
    FROM public.bookings b
    WHERE b.status = 'approved'
      AND b.reminder_sent = false
      AND b.date = (now() AT TIME ZONE 'Asia/Kolkata')::date
      AND (b.date + b.start_time) AT TIME ZONE 'Asia/Kolkata'
          BETWEEN now() AND now() + INTERVAL '15 minutes'
  LOOP
    SELECT name INTO v_room FROM public.rooms WHERE id = v_booking.room_id;
    v_body := '"' || v_booking.title || '" in ' || COALESCE(v_room, 'room') ||
              ' starts at ' || to_char(v_booking.start_time, 'HH24:MI') ||
              ' (' || to_char(v_booking.end_time, 'HH24:MI') || ' end).';

    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_booking.user_id, 'reminder', 'Meeting starting soon ⏰', v_body, v_booking.id);

    FOR v_member IN
      SELECT email FROM public.booking_members
      WHERE booking_id = v_booking.id AND status = 'accepted'
    LOOP
      PERFORM public.notify_user_by_email(
        v_member.email, 'reminder', 'Meeting starting soon ⏰', v_body, v_booking.id
      );
    END LOOP;

    UPDATE public.bookings SET reminder_sent = true WHERE id = v_booking.id;
  END LOOP;
END;
$$;

-- Trigger: when an owner (non-admin) edits scheduling fields, reset status to pending_admin
CREATE OR REPLACE FUNCTION public.reset_booking_on_owner_edit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Skip if admin is making the change (admin edits should stand)
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  -- Only fire on scheduling/content changes, not status-only changes
  IF NEW.date = OLD.date
     AND NEW.start_time = OLD.start_time
     AND NEW.end_time = OLD.end_time
     AND NEW.room_id = OLD.room_id
     AND NEW.title = OLD.title THEN
    RETURN NEW;
  END IF;

  -- If owner edited an already-approved booking, reset to pending_admin
  IF OLD.status = 'approved' AND NEW.status = OLD.status THEN
    NEW.status := 'pending_admin';
    NEW.reminder_sent := false;
  END IF;

  -- Reset reminder flag whenever schedule changes
  NEW.reminder_sent := false;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reset_booking_on_owner_edit ON public.bookings;
CREATE TRIGGER trg_reset_booking_on_owner_edit
BEFORE UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.reset_booking_on_owner_edit();

-- Enable pg_cron + schedule reminders every 5 minutes
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$ BEGIN
  PERFORM cron.unschedule('booking-reminders-5min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'booking-reminders-5min',
  '*/5 * * * *',
  $$ SELECT public.send_booking_reminders(); $$
);