CREATE OR REPLACE FUNCTION public.auto_approve_imminent_bookings()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_booking RECORD;
  v_room TEXT;
  v_owner TEXT;
  v_admin RECORD;
  v_title TEXT;
  v_body TEXT;
  v_err TEXT;
  v_already_notified BOOLEAN;
  v_reason TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.has_role(auth.uid(), 'admin') THEN
    RETURN;
  END IF;

  FOR v_booking IN
    SELECT b.*,
      CASE
        WHEN ((b.date::text || ' ' || b.start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata')
             BETWEEN now() AND now() + INTERVAL '15 minutes' THEN 'imminent'
        WHEN ((b.date::text || ' ' || b.start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata') <= now()
             AND ((b.date::text || ' ' || b.end_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata') > now()
             THEN 'active_now'
        WHEN b.pending_admin_since IS NOT NULL
             AND b.pending_admin_since <= now() - INTERVAL '5 minutes'
             AND ((b.date::text || ' ' || b.end_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata') > now()
             THEN 'stale'
      END AS trigger_reason
    FROM public.bookings b
    WHERE b.status = 'pending_admin'
      AND (
        -- imminent: starts within 15 min
        ((b.date::text || ' ' || b.start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata')
          BETWEEN now() AND now() + INTERVAL '15 minutes'
        -- active_now: start already passed but end still in future (edge case: pending_admin was set right at/after start)
        OR (
          ((b.date::text || ' ' || b.start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata') <= now()
          AND ((b.date::text || ' ' || b.end_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata') > now()
        )
        -- stale: waited over 5 min for admin, meeting hasn't fully ended yet
        OR (
          b.pending_admin_since IS NOT NULL
          AND b.pending_admin_since <= now() - INTERVAL '5 minutes'
          AND ((b.date::text || ' ' || b.end_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata') > now()
        )
      )
  LOOP
    v_reason := v_booking.trigger_reason;
    BEGIN
      UPDATE public.bookings
      SET status = 'approved'
      WHERE id = v_booking.id AND status = 'pending_admin';
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;

      SELECT EXISTS (
        SELECT 1 FROM public.notifications
        WHERE booking_id = v_booking.id AND type = 'booking_conflict_urgent'
      ) INTO v_already_notified;

      IF NOT v_already_notified THEN
        SELECT name INTO v_room FROM public.rooms WHERE id = v_booking.room_id;
        SELECT COALESCE(full_name, email) INTO v_owner
          FROM public.profiles WHERE user_id = v_booking.user_id;

        v_title := 'Urgent: pending booking has a conflict';
        v_body  := COALESCE(v_owner, 'A user') || '''s booking "' || v_booking.title || '" in ' ||
                   COALESCE(v_room, 'a room') || ' on ' || v_booking.date || ' at ' ||
                   to_char(v_booking.start_time, 'HH24:MI') || '–' || to_char(v_booking.end_time, 'HH24:MI') ||
                   ' could not be auto-approved (' ||
                   CASE WHEN v_reason = 'imminent' THEN 'starts within 15 minutes'
                        WHEN v_reason = 'active_now' THEN 'meeting is already in progress'
                        ELSE 'has been awaiting admin approval for over 5 minutes' END ||
                   ') due to a conflict: ' || v_err || '. Please review manually.';

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
$function$;
