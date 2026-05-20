-- Prevent non-admin owners from modifying admin-only fields on bookings
CREATE OR REPLACE FUNCTION public.prevent_user_admin_field_tampering()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admins bypass entirely
  IF private.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RETURN NEW;
  END IF;

  -- System / service-role contexts (no auth.uid) bypass
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.reminder_sent IS DISTINCT FROM OLD.reminder_sent
     AND NEW.reminder_sent <> false THEN
    -- Allow trigger-driven reset to false (reset_booking_on_owner_edit),
    -- but never allow user-driven flip to true.
    RAISE EXCEPTION 'reminder_sent can only be changed by admins or the system';
  END IF;

  IF NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason THEN
    RAISE EXCEPTION 'rejection_reason can only be set by admins';
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'Booking ownership can only be reassigned by admins';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_user_admin_field_tampering ON public.bookings;
CREATE TRIGGER prevent_user_admin_field_tampering
BEFORE UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.prevent_user_admin_field_tampering();

REVOKE EXECUTE ON FUNCTION public.prevent_user_admin_field_tampering() FROM PUBLIC, anon, authenticated;

-- Further tighten shares_booking: require a confirmed (accepted) active membership,
-- not just a pending invite. This blocks profile enumeration by mass-inviting emails.
CREATE OR REPLACE FUNCTION private.shares_booking(_viewer uuid, _target uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    -- Viewer organized a current/active booking that target accepted
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    WHERE b.user_id = _viewer
      AND bm.user_id = _target
      AND b.status IN ('approved', 'pending_admin', 'pending_members', 'needs_replacement')
      AND b.date >= CURRENT_DATE
      AND bm.status = 'accepted'
    UNION ALL
    -- Target organized a current/active booking that viewer accepted
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    WHERE b.user_id = _target
      AND bm.user_id = _viewer
      AND b.status IN ('approved', 'pending_admin', 'pending_members', 'needs_replacement')
      AND b.date >= CURRENT_DATE
      AND bm.status = 'accepted'
  )
$$;
