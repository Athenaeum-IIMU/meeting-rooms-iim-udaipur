CREATE OR REPLACE FUNCTION public.trim_log_tables()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Keep only today's records (delete everything up to and including yesterday)
  DELETE FROM public.booking_attempts    WHERE created_at < CURRENT_DATE;
  DELETE FROM public.audit_log           WHERE created_at < CURRENT_DATE;
  DELETE FROM public.email_delivery_log  WHERE created_at < CURRENT_DATE;
  DELETE FROM public.notifications       WHERE created_at < CURRENT_DATE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trim_log_tables() FROM PUBLIC, anon, authenticated;