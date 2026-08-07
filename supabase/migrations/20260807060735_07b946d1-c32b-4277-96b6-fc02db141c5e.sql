CREATE OR REPLACE FUNCTION public.audit_booking_deleted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_room TEXT;
BEGIN
  -- Skip automated/cron deletions (no authenticated actor)
  IF v_actor IS NULL THEN RETURN OLD; END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = OLD.room_id;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    'booking_deleted',
    'booking',
    OLD.id,
    'Deleted "' || OLD.title || '" (' || COALESCE(v_room, 'room') || ' on ' || OLD.date ||
    ' ' || to_char(OLD.start_time, 'HH24:MI') || '–' || to_char(OLD.end_time, 'HH24:MI') || ')',
    jsonb_build_object(
      'title', OLD.title,
      'room_id', OLD.room_id,
      'room_name', v_room,
      'date', OLD.date,
      'start_time', OLD.start_time,
      'end_time', OLD.end_time,
      'owner_id', OLD.user_id,
      'last_status', OLD.status
    )
  );
  RETURN OLD;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.audit_booking_deleted() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_audit_booking_deleted ON public.bookings;
CREATE TRIGGER trg_audit_booking_deleted
BEFORE DELETE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.audit_booking_deleted();