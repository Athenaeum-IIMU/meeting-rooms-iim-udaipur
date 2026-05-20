-- 1) Remove bookings from realtime publication to stop broadcasting approved
--    booking row changes to every authenticated subscriber.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'bookings'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime DROP TABLE public.bookings';
  END IF;
END $$;

-- 2) Revoke EXECUTE from authenticated / anon / PUBLIC on all SECURITY DEFINER
--    helpers that don't need to be invoked directly by signed-in users.
--    These are only called from triggers (which run as the function owner)
--    or from server-side cron, so removing direct EXECUTE is safe.
REVOKE EXECUTE ON FUNCTION public.get_actor_email(uuid)          FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_user_by_email(text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_send_email_secret()        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.send_booking_reminders()       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_unapproved_past_bookings() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_blocked_slot(uuid, date, time, time) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_booking_conflict(uuid, date, time, time, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_user_time_overlap(uuid, date, time, time, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_user_daily_hours(uuid, date, uuid) FROM PUBLIC, anon, authenticated;

-- has_role() and shares_booking() intentionally remain executable by
-- 'authenticated' because they are referenced from RLS policy expressions
-- (e.g. user_roles, profiles, bookings, audit_log). Revoking EXECUTE would
-- cause every RLS policy that calls them to deny access. This is the
-- Supabase-recommended pattern for SECURITY DEFINER role helpers.
