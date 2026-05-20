
-- 1) Enforce iimu.ac.in domain server-side during signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.email IS NULL OR LOWER(NEW.email) NOT LIKE '%@iimu.ac.in' THEN
    RAISE EXCEPTION 'Only @iimu.ac.in accounts are allowed to sign in';
  END IF;

  INSERT INTO public.profiles (user_id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');

  UPDATE public.booking_members
  SET user_id = NEW.id
  WHERE user_id IS NULL
    AND LOWER(email) = LOWER(NEW.email);

  RETURN NEW;
END;
$function$;

-- 2) Lock down cleanup_unapproved_past_bookings to admins only
CREATE OR REPLACE FUNCTION public.cleanup_unapproved_past_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only admins (or internal/service_role callers where auth.uid() is NULL) may run this
  IF auth.uid() IS NOT NULL AND NOT public.has_role(auth.uid(), 'admin') THEN
    RETURN;
  END IF;

  UPDATE public.bookings
  SET status = 'cancelled',
      rejection_reason = COALESCE(rejection_reason, 'Auto-cancelled: not enough members confirmed within 30 minutes of start')
  WHERE status = 'needs_replacement'
    AND ((date::text || ' ' || start_time::text)::timestamp AT TIME ZONE 'Asia/Kolkata')
        <= now() + INTERVAL '30 minutes';

  DELETE FROM public.booking_members
  WHERE booking_id IN (
    SELECT id FROM public.bookings
    WHERE date < CURRENT_DATE AND status <> 'approved'
  );
  DELETE FROM public.notifications
  WHERE booking_id IN (
    SELECT id FROM public.bookings
    WHERE date < CURRENT_DATE AND status <> 'approved'
  );
  DELETE FROM public.bookings
  WHERE date < CURRENT_DATE AND status <> 'approved';
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.cleanup_unapproved_past_bookings() FROM PUBLIC, anon, authenticated;
