REVOKE ALL ON FUNCTION public.auto_approve_on_pending_admin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.track_pending_admin_since() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_reevaluate_on_slot_freed() FROM PUBLIC, anon, authenticated;