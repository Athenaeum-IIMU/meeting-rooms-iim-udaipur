CREATE OR REPLACE FUNCTION public.check_user_time_overlap(p_user_id uuid, p_date date, p_start_time time without time zone, p_end_time time without time zone, p_exclude_booking_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only allow users to check their own schedule (admins can check anyone)
  IF p_user_id IS DISTINCT FROM auth.uid() AND NOT public.has_role(auth.uid(), 'admin') THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.bookings b
    WHERE b.date = p_date
      AND b.status IN ('approved', 'pending_admin', 'pending_members')
      AND (p_exclude_booking_id IS NULL OR b.id != p_exclude_booking_id)
      AND b.start_time < p_end_time
      AND b.end_time > p_start_time
      AND (
        b.user_id = p_user_id
        OR EXISTS (
          SELECT 1 FROM public.booking_members bm
          WHERE bm.booking_id = b.id
            AND bm.email IN (SELECT email FROM public.profiles WHERE user_id = p_user_id)
            AND bm.status != 'rejected'
        )
      )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_daily_hours(p_user_id uuid, p_date date, p_exclude_booking_id uuid DEFAULT NULL::uuid)
 RETURNS interval
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only allow users to check their own daily hours (admins can check anyone)
  IF p_user_id IS DISTINCT FROM auth.uid() AND NOT public.has_role(auth.uid(), 'admin') THEN
    RETURN INTERVAL '0 hours';
  END IF;

  RETURN COALESCE((
    SELECT SUM(end_time - start_time)
    FROM public.bookings
    WHERE user_id = p_user_id
      AND date = p_date
      AND status IN ('approved', 'pending_admin', 'pending_members')
      AND (p_exclude_booking_id IS NULL OR id != p_exclude_booking_id)
  ), INTERVAL '0 hours');
END;
$function$;