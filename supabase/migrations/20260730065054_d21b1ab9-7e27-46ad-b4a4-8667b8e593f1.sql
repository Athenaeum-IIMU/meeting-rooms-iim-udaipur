CREATE OR REPLACE FUNCTION public.validate_booking_date()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot book a date in the past';
  END IF;
  IF NEW.date > CURRENT_DATE + INTERVAL '1 day' THEN
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
BEGIN
  IF NEW.date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot waitlist a date in the past';
  END IF;
  IF NEW.date > CURRENT_DATE + INTERVAL '1 day' THEN
    RAISE EXCEPTION 'Cannot waitlist more than 1 day in advance';
  END IF;
  IF NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'End time must be after start time';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.validate_booking_date() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_waitlist_entry() FROM PUBLIC, anon, authenticated;