-- Prevent members from re-assigning themselves to other bookings or spoofing identity
CREATE OR REPLACE FUNCTION public.prevent_booking_member_tampering()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admins bypass
  IF public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  IF NEW.booking_id IS DISTINCT FROM OLD.booking_id THEN
    RAISE EXCEPTION 'Cannot change booking_id of a membership';
  END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'Cannot change user_id of a membership';
  END IF;
  IF LOWER(NEW.email) IS DISTINCT FROM LOWER(OLD.email) THEN
    RAISE EXCEPTION 'Cannot change email of a membership';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_booking_member_tampering_trg ON public.booking_members;
CREATE TRIGGER prevent_booking_member_tampering_trg
BEFORE UPDATE ON public.booking_members
FOR EACH ROW
EXECUTE FUNCTION public.prevent_booking_member_tampering();

-- Tighten the UPDATE policy: members may only update their own row, status must be valid
DROP POLICY IF EXISTS "Members can update own status" ON public.booking_members;
CREATE POLICY "Members can update own status"
ON public.booking_members
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (
  user_id = auth.uid()
  AND status IN ('pending', 'accepted', 'rejected')
);