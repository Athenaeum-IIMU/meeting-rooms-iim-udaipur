
CREATE OR REPLACE FUNCTION public.log_booking_attempt(
  p_room_id uuid,
  p_title text,
  p_date date,
  p_start_time time,
  p_end_time time,
  p_member_emails text[],
  p_error_message text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  SELECT email INTO v_email FROM public.profiles WHERE user_id = v_uid LIMIT 1;
  INSERT INTO public.booking_attempts
    (user_id, user_email, room_id, title, date, start_time, end_time,
     member_emails, success, error_message)
  VALUES
    (v_uid, v_email, p_room_id, p_title, p_date, p_start_time, p_end_time,
     COALESCE(p_member_emails, ARRAY[]::text[]), false, p_error_message);
END $$;

GRANT EXECUTE ON FUNCTION public.log_booking_attempt(uuid, text, date, time, time, text[], text) TO authenticated;
