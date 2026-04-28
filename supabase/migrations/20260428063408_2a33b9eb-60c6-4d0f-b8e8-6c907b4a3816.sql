
-- Revoke EXECUTE from all internal/trigger SECURITY DEFINER functions
-- These are only invoked by triggers or from within the database, never by clients directly.
REVOKE EXECUTE ON FUNCTION public.handle_booking_member_response() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_booking_status_change() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_booking_modified() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.audit_slot_unblocked() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_slot_blocked() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_booking_date() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_waitlist_on_freed() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_waitlist_entry() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_booking_member_invite() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.audit_booking_modified() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.audit_slot_blocked() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reset_booking_on_owner_edit() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.audit_booking_status_change() FROM PUBLIC, anon, authenticated;
