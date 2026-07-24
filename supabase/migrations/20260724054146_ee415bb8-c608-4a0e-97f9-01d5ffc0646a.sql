select cron.unschedule('auto-approve-imminent-bookings');

select cron.schedule(
  'auto-approve-imminent-bookings',
  '*/20 * * * *', -- every 20 minutes
  $$
  select public.auto_approve_imminent_bookings();
  $$
);