
CREATE OR REPLACE FUNCTION public.accept_booking_invite_atomic(p_member_id uuid, p_accept boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member RECORD;
  v_new_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT lower(email) INTO v_email FROM public.profiles WHERE user_id = v_uid LIMIT 1;

  SELECT bm.id, bm.booking_id, bm.email, bm.user_id, bm.status
  INTO v_member
  FROM public.booking_members bm
  WHERE bm.id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invite not found';
  END IF;

  IF v_member.user_id IS DISTINCT FROM v_uid
     AND (v_email IS NULL OR lower(v_member.email) <> v_email) THEN
    RAISE EXCEPTION 'You cannot respond to this invite';
  END IF;

  v_new_status := CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END;

  UPDATE public.booking_members
  SET status = v_new_status,
      user_id = v_uid
  WHERE id = p_member_id;
END $function$;

REVOKE ALL ON FUNCTION public.accept_booking_invite_atomic(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_booking_invite_atomic(uuid, boolean) TO authenticated;
