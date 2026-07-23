
-- Simplify auto-approval: approve any pending_admin booking older than 1 minute.
-- Run cron every minute but keep the function extremely cheap (partial index scan; no-op when empty).

CREATE OR REPLACE FUNCTION public.auto_approve_imminent_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
  has_conflict boolean;
  admin_rec RECORD;
BEGIN
  -- Fast exit if nothing pending long enough (uses idx_bookings_pending_admin)
  IF NOT EXISTS (
    SELECT 1 FROM public.bookings
    WHERE status = 'pending_admin'
      AND COALESCE(pending_admin_since, created_at) <= now() - interval '1 minute'
      AND end_time > now()
    LIMIT 1
  ) THEN
    RETURN;
  END IF;

  FOR b IN
    SELECT * FROM public.bookings
    WHERE status = 'pending_admin'
      AND COALESCE(pending_admin_since, created_at) <= now() - interval '1 minute'
      AND end_time > now()
    ORDER BY start_time ASC
  LOOP
    -- Conflict check: any other approved booking overlapping this one in the same room
    SELECT EXISTS (
      SELECT 1 FROM public.bookings x
      WHERE x.room_id = b.room_id
        AND x.id <> b.id
        AND x.status = 'approved'
        AND x.start_time < b.end_time
        AND x.end_time > b.start_time
    ) OR EXISTS (
      SELECT 1 FROM public.blocked_slots bs
      WHERE bs.room_id = b.room_id
        AND bs.start_time < b.end_time
        AND bs.end_time > b.start_time
    ) INTO has_conflict;

    IF has_conflict THEN
      -- Notify admins about the conflict; do not auto-approve
      FOR admin_rec IN
        SELECT ur.user_id FROM public.user_roles ur WHERE ur.role = 'admin'
      LOOP
        INSERT INTO public.notifications (user_id, type, title, message, booking_id)
        VALUES (
          admin_rec.user_id,
          'conflict_pending',
          'Pending booking has a conflict',
          'Booking "' || COALESCE(b.title, '(untitled)') || '" could not be auto-approved due to a conflict. Please review.',
          b.id
        )
        ON CONFLICT DO NOTHING;
      END LOOP;
    ELSE
      UPDATE public.bookings
      SET status = 'approved',
          approved_at = now(),
          approved_by = NULL
      WHERE id = b.id AND status = 'pending_admin';
    END IF;
  END LOOP;
END;
$$;

-- Reschedule cron to run every minute (cheap due to fast exit + partial index)
DO $$
DECLARE j int;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'auto-approve-imminent-bookings';
  IF j IS NOT NULL THEN
    PERFORM cron.unschedule(j);
  END IF;
END $$;

SELECT cron.schedule(
  'auto-approve-imminent-bookings',
  '* * * * *',
  $$ SELECT public.auto_approve_imminent_bookings(); $$
);
