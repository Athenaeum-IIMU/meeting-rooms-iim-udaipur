CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.notifications WHERE created_at < now() - INTERVAL '1 day';
  DELETE FROM public.email_delivery_log WHERE created_at < now() - INTERVAL '1 day';
  DELETE FROM public.audit_log WHERE created_at < now() - INTERVAL '30 days';

  DELETE FROM public.booking_members
    WHERE booking_id IN (SELECT id FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '1 day');
  DELETE FROM public.notifications
    WHERE booking_id IN (SELECT id FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '1 day');
  DELETE FROM public.email_delivery_log
    WHERE booking_id IN (SELECT id FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '1 day');
  DELETE FROM public.waitlist WHERE date < CURRENT_DATE - INTERVAL '1 day';
  DELETE FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '1 day';
  DELETE FROM public.blocked_slots WHERE date < CURRENT_DATE - INTERVAL '1 day';
END;
$function$;

SELECT public.cleanup_old_data();