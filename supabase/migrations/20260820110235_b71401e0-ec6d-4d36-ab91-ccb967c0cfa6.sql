CREATE OR REPLACE FUNCTION public.ist_today()
RETURNS date
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$ SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date $$;

REVOKE EXECUTE ON FUNCTION public.ist_today() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ist_today() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.validate_booking_date()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NEW.date < v_today THEN
    RAISE EXCEPTION 'Cannot book a date in the past';
  END IF;
  IF NEW.date > v_today + 1 THEN
    RAISE EXCEPTION 'Cannot book more than 1 day in advance';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.validate_waitlist_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF NEW.date < v_today THEN
    RAISE EXCEPTION 'Cannot waitlist a date in the past';
  END IF;
  IF NEW.date > v_today + 1 THEN
    RAISE EXCEPTION 'Cannot waitlist more than 1 day in advance';
  END IF;
  IF NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'End time must be after start time';
  END IF;
  RETURN NEW;
END;
$function$;