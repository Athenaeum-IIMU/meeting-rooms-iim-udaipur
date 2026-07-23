
CREATE OR REPLACE FUNCTION public.trim_log_tables()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Keep only today and yesterday for audit_log and booking_attempts
  DELETE FROM public.booking_attempts WHERE created_at < (CURRENT_DATE - INTERVAL '1 day');
  DELETE FROM public.audit_log       WHERE created_at < (CURRENT_DATE - INTERVAL '1 day');

  -- Other logs: keep 30 days (unchanged behavior for these)
  DELETE FROM public.email_delivery_log WHERE created_at < now() - INTERVAL '30 days';
  DELETE FROM public.notifications      WHERE read = true AND created_at < now() - INTERVAL '30 days';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trim_log_tables() FROM PUBLIC, anon, authenticated;

-- Run once immediately to purge existing old rows
SELECT public.trim_log_tables();
