
CREATE OR REPLACE FUNCTION public.accept_booking_invite_atomic(
  p_member_id uuid,
  p_accept boolean
) RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_member RECORD;
  v_new_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT bm.id, bm.booking_id, bm.email, bm.user_id, bm.status
  INTO v_member
  FROM public.booking_members bm
  WHERE bm.id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invite not found';
  END IF;

  -- Verify caller owns this invite (by uid or by email match on profile)
  IF v_member.user_id IS DISTINCT FROM v_uid
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles p
       WHERE p.user_id = v_uid AND lower(p.email) = lower(v_member.email)
     ) THEN
    RAISE EXCEPTION 'You cannot respond to this invite';
  END IF;

  v_new_status := CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END;

  -- The BEFORE UPDATE trigger validate_booking_member_trigger enforces
  -- cross-room overlap and the 4-hour daily limit for the accepting user.
  UPDATE public.booking_members
  SET status = v_new_status,
      user_id = v_uid
  WHERE id = p_member_id;
END $$;

REVOKE ALL ON FUNCTION public.accept_booking_invite_atomic(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_booking_invite_atomic(uuid, boolean) TO authenticated;
