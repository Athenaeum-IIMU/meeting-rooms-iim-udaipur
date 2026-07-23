
DO $$
DECLARE j int;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'auto-approve-imminent-bookings';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;

SELECT cron.schedule(
  'auto-approve-imminent-bookings',
  '*/10 * * * *',
  $$ SELECT public.auto_approve_imminent_bookings(); $$
);
