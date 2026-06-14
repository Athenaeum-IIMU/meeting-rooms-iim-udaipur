
CREATE TABLE public.booking_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  user_email text,
  room_id uuid,
  title text,
  date date,
  start_time time,
  end_time time,
  member_emails text[],
  success boolean NOT NULL,
  error_message text,
  booking_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.booking_attempts TO authenticated;
GRANT ALL ON public.booking_attempts TO service_role;

ALTER TABLE public.booking_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view all booking attempts"
ON public.booking_attempts FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

CREATE INDEX idx_booking_attempts_created_at ON public.booking_attempts(created_at DESC);

-- Wrapper that logs every attempt (success or failure) then returns/re-raises.
CREATE OR REPLACE FUNCTION public.create_booking_logged(
  p_room_id uuid,
  p_title text,
  p_date date,
  p_start_time time,
  p_end_time time,
  p_member_emails text[] DEFAULT ARRAY[]::text[]
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_booking_id uuid;
  v_err text;
BEGIN
  SELECT email INTO v_email FROM public.profiles WHERE user_id = v_uid LIMIT 1;

  BEGIN
    v_booking_id := public.create_booking_atomic(
      p_room_id, p_title, p_date, p_start_time, p_end_time, p_member_emails
    );

    INSERT INTO public.booking_attempts
      (user_id, user_email, room_id, title, date, start_time, end_time,
       member_emails, success, booking_id)
    VALUES
      (v_uid, v_email, p_room_id, p_title, p_date, p_start_time, p_end_time,
       p_member_emails, true, v_booking_id);

    RETURN v_booking_id;
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
    INSERT INTO public.booking_attempts
      (user_id, user_email, room_id, title, date, start_time, end_time,
       member_emails, success, error_message)
    VALUES
      (v_uid, v_email, p_room_id, p_title, p_date, p_start_time, p_end_time,
       p_member_emails, false, v_err);
    RAISE EXCEPTION '%', v_err;
  END;
END $$;

GRANT EXECUTE ON FUNCTION public.create_booking_logged(uuid, text, date, time, time, text[]) TO authenticated;
