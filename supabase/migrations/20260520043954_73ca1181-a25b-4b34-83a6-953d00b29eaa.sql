
DO $$
DECLARE
  r RECORD;
  keep_for_authenticated TEXT[] := ARRAY[
    'has_role',
    'shares_booking',
    'check_blocked_slot',
    'check_booking_conflict',
    'check_user_time_overlap',
    'get_user_daily_hours',
    'cleanup_unapproved_past_bookings'
  ];
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.proname <> ALL(keep_for_authenticated)
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC, anon, authenticated;',
                   r.nspname, r.proname, r.args);
  END LOOP;
END$$;
