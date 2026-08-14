-- Re-create as full UPDATE triggers, named so they run AFTER reset_booking_on_owner_edit
DROP TRIGGER IF EXISTS trg_auto_approve_on_pending_admin ON public.bookings;
DROP TRIGGER IF EXISTS trg_track_pending_admin_since ON public.bookings;

CREATE TRIGGER trg_zz1_auto_approve_on_pending_admin
BEFORE INSERT OR UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.auto_approve_on_pending_admin();

CREATE TRIGGER trg_zz2_track_pending_admin_since
BEFORE INSERT OR UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.track_pending_admin_since();

-- Rescue currently stuck pending_admin bookings with no clash
SELECT public.auto_approve_imminent_bookings();