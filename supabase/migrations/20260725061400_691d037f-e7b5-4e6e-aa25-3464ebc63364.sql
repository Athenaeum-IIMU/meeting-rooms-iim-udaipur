-- Fix member invite accept/decline flow blocked by booking status escalation triggers.

CREATE OR REPLACE FUNCTION public.prevent_booking_member_tampering()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email text;
BEGIN
  -- Admins bypass.
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  -- System-level linking from signup/background jobs.
  IF auth.uid() IS NULL AND OLD.user_id IS NULL AND NEW.user_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.booking_id IS DISTINCT FROM OLD.booking_id THEN
    RAISE EXCEPTION 'Cannot change booking_id of a membership';
  END IF;

  IF LOWER(NEW.email) IS DISTINCT FROM LOWER(OLD.email) THEN
    RAISE EXCEPTION 'Cannot change email of a membership';
  END IF;

  -- The invite-response RPC may link an unlinked invite to the signed-in
  -- user, but only when that user's profile email matches the invited email.
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    SELECT lower(email) INTO v_email
    FROM public.profiles
    WHERE user_id = auth.uid()
    LIMIT 1;

    IF OLD.user_id IS NULL
       AND NEW.user_id = auth.uid()
       AND v_email = lower(OLD.email) THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Cannot change user_id of a membership';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_status_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_min_members int;
  v_accepted int;
  v_pending int;
  v_has_conflict boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status = 'rejected' THEN
    RAISE EXCEPTION 'Only admins can reject bookings';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status = 'approved' THEN
    -- Trusted auto-approval is allowed only after all invited members have
    -- responded, the room's minimum headcount is met, and there is no room or
    -- blocked-slot conflict. This preserves the no-manual-admin flow while
    -- preventing arbitrary client-side approval escalation.
    SELECT COALESCE(r.min_members, 3)
    INTO v_min_members
    FROM public.rooms r
    WHERE r.id = NEW.room_id;

    SELECT
      COUNT(*) FILTER (WHERE bm.status = 'accepted'),
      COUNT(*) FILTER (WHERE bm.status = 'pending')
    INTO v_accepted, v_pending
    FROM public.booking_members bm
    WHERE bm.booking_id = NEW.id;

    SELECT EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.room_id = NEW.room_id
        AND b.date = NEW.date
        AND b.id <> NEW.id
        AND b.status = 'approved'
        AND b.start_time < NEW.end_time
        AND b.end_time > NEW.start_time
    ) OR EXISTS (
      SELECT 1
      FROM public.blocked_slots bs
      WHERE bs.room_id = NEW.room_id
        AND bs.date = NEW.date
        AND bs.start_time < NEW.end_time
        AND bs.end_time > NEW.start_time
    )
    INTO v_has_conflict;

    IF OLD.status IN ('pending_members', 'needs_replacement', 'pending_admin')
       AND COALESCE(v_pending, 0) = 0
       AND COALESCE(v_accepted, 0) + 1 >= COALESCE(v_min_members, 3)
       AND NOT COALESCE(v_has_conflict, true) THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Only admins can approve bookings';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.prevent_booking_member_tampering() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_status_escalation() FROM PUBLIC, anon, authenticated;