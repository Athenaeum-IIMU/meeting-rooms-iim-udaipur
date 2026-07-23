
-- 1) Reduce auto-approve cron frequency from every minute to every 2 minutes.
--    5-min-stale and 15-min-imminent windows still comfortably satisfied.
DO $$
DECLARE
  jid bigint;
BEGIN
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'auto-approve-imminent-bookings';
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;
  PERFORM cron.schedule('auto-approve-imminent-bookings', '*/2 * * * *',
    $sql$SELECT public.auto_approve_imminent_bookings();$sql$);
END $$;

-- 2) Tiny partial index so the per-run scan is O(pending) not O(all bookings).
CREATE INDEX IF NOT EXISTS idx_bookings_pending_admin
  ON public.bookings (start_time, end_time)
  WHERE status = 'pending_admin';

-- 3) Trim log tables inside the existing daily cleanup so they stop growing.
--    Keep 30 days of audit/attempts/email logs and read notifications.
CREATE OR REPLACE FUNCTION public.trim_log_tables()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.booking_attempts   WHERE created_at < now() - interval '30 days';
  DELETE FROM public.audit_log          WHERE created_at < now() - interval '30 days';
  DELETE FROM public.email_delivery_log WHERE created_at < now() - interval '30 days';
  DELETE FROM public.notifications      WHERE read = true AND created_at < now() - interval '30 days';
END $$;

REVOKE EXECUTE ON FUNCTION public.trim_log_tables() FROM PUBLIC, anon, authenticated;

-- 4) Hook trim into the daily cleanup cron (separate job, runs after cleanup).
DO $$
DECLARE
  jid bigint;
BEGIN
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'daily-trim-logs';
  IF jid IS NOT NULL THEN
    PERFORM cron.unschedule(jid);
  END IF;
  PERFORM cron.schedule('daily-trim-logs', '15 3 * * *',
    $sql$SELECT public.trim_log_tables();$sql$);
END $$;

-- Run once now to reclaim space immediately.
SELECT public.trim_log_tables();
