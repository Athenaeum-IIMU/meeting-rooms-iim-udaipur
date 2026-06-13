CREATE OR REPLACE FUNCTION public.create_booking_atomic(p_room_id uuid, p_title text, p_date date, p_start_time time without time zone, p_end_time time without time zone, p_member_emails text[] DEFAULT ARRAY[]::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_booking_id uuid;
  v_status text;
  v_email text;
  v_missing text[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Require every invited member to already have a profile (i.e. have signed in
  -- at least once), unless caller is an admin. Keeps invites limited to real
  -- platform users so they actually receive in-app notifications.
  IF coalesce(array_length(p_member_emails,1),0) > 0
     AND NOT public.has_role(v_uid, 'admin') THEN
    SELECT array_agg(e ORDER BY e) INTO v_missing
    FROM (
      SELECT lower(trim(unnest(p_member_emails))) AS e
    ) src
    WHERE NOT EXISTS (
      SELECT 1 FROM public.profiles p WHERE lower(p.email) = src.e
    );
    IF v_missing IS NOT NULL AND array_length(v_missing,1) > 0 THEN
      RAISE EXCEPTION 'NOT_REGISTERED:%', array_to_string(v_missing, ',');
    END IF;
  END IF;

  v_status := CASE WHEN coalesce(array_length(p_member_emails,1),0) > 0
                   THEN 'pending_members' ELSE 'pending_admin' END;

  INSERT INTO public.bookings (room_id, user_id, title, date, start_time, end_time, status)
  VALUES (p_room_id, v_uid, p_title, p_date, p_start_time, p_end_time, v_status)
  RETURNING id INTO v_booking_id;

  IF coalesce(array_length(p_member_emails,1),0) > 0 THEN
    FOREACH v_email IN ARRAY p_member_emails LOOP
      INSERT INTO public.booking_members (booking_id, email)
      VALUES (v_booking_id, lower(trim(v_email)));
    END LOOP;
  END IF;

  RETURN v_booking_id;
END $function$;