
-- Auto-approve pending bookings starting within 5 minutes; notify admins on conflicts.
CREATE OR REPLACE FUNCTION public.auto_approve_imminent_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_room TEXT;
  v_owner TEXT;
  v_admin RECORD;
  v_title TEXT;
  v_body TEXT;
  v_err TEXT;
  v_already_notified BOOLEAN;
BEGIN
  -- Only admins or internal/service_role callers (auth.uid() IS NULL) may run.
  IF auth.uid() IS NOT NULL AND NOT public.has_role(auth.uid(), 'admin') THEN
    RETURN;
  END IF;

  FOR v_booking IN
    SELECT b.*
    FROM public.bookings b
    WHERE b.status = 'pending_admin'
      AND ((b.date::text || ' ' || b.start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata')
          BETWEEN now() AND now() + INTERVAL '5 minutes'
  LOOP
    BEGIN
      -- Try to approve. Existing triggers will handle notifications & auto-reject overlaps.
      UPDATE public.bookings
      SET status = 'approved'
      WHERE id = v_booking.id AND status = 'pending_admin';
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;

      -- Skip if we've already alerted admins for this booking.
      SELECT EXISTS (
        SELECT 1 FROM public.notifications
        WHERE booking_id = v_booking.id AND type = 'booking_conflict_urgent'
      ) INTO v_already_notified;

      IF NOT v_already_notified THEN
        SELECT name INTO v_room FROM public.rooms WHERE id = v_booking.room_id;
        SELECT COALESCE(full_name, email) INTO v_owner
          FROM public.profiles WHERE user_id = v_booking.user_id;

        v_title := 'Urgent: imminent booking has a conflict';
        v_body  := COALESCE(v_owner, 'A user') || '''s booking "' || v_booking.title || '" in ' ||
                   COALESCE(v_room, 'a room') || ' on ' || v_booking.date || ' at ' ||
                   to_char(v_booking.start_time, 'HH24:MI') || '–' || to_char(v_booking.end_time, 'HH24:MI') ||
                   ' starts within 5 minutes but could not be auto-approved due to a conflict: ' || v_err ||
                   '. Please review manually.';

        FOR v_admin IN
          SELECT ur.user_id FROM public.user_roles ur WHERE ur.role = 'admin'
        LOOP
          INSERT INTO public.notifications (user_id, type, title, body, booking_id)
          VALUES (v_admin.user_id, 'booking_conflict_urgent', v_title, v_body, v_booking.id);
        END LOOP;
      END IF;
    END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.auto_approve_imminent_bookings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_approve_imminent_bookings() TO service_role, authenticated;

-- Schedule every minute
DO $$
BEGIN
  PERFORM cron.unschedule('auto-approve-imminent-bookings');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'auto-approve-imminent-bookings',
  '* * * * *',
  $cron$ SELECT public.auto_approve_imminent_bookings(); $cron$
);
