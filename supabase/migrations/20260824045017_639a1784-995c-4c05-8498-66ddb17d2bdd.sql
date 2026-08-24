
-- 1) Richer booking status change audit (includes owner, self-cancels and system actions)
CREATE OR REPLACE FUNCTION public.audit_booking_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_actor_email TEXT;
  v_room TEXT;
  v_owner_email TEXT;
  v_actor_label TEXT;
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('approved', 'rejected', 'cancelled', 'needs_replacement') THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
  v_owner_email := public.get_actor_email(NEW.user_id);

  IF v_actor IS NULL THEN
    v_actor_label := 'System';
    v_actor_email := NULL;
  ELSE
    v_actor_email := public.get_actor_email(v_actor);
    IF public.has_role(v_actor, 'admin') THEN
      v_actor_label := 'Admin';
    ELSIF v_actor = NEW.user_id THEN
      v_actor_label := 'Organiser';
    ELSE
      v_actor_label := 'User';
    END IF;
  END IF;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    v_actor_email,
    'booking_' || NEW.status,
    'booking',
    NEW.id,
    v_actor_label || ' set "' || NEW.title || '" to ' || NEW.status ||
    ' — booked by ' || COALESCE(v_owner_email, 'unknown') ||
    ' (' || COALESCE(v_room, 'room') || ' on ' || NEW.date ||
    ' ' || to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') || ')',
    jsonb_build_object(
      'from_status', OLD.status,
      'to_status', NEW.status,
      'actor_role', v_actor_label,
      'owner_id', NEW.user_id,
      'owner_email', v_owner_email,
      'room_name', v_room,
      'date', NEW.date,
      'start_time', NEW.start_time::text,
      'end_time', NEW.end_time::text,
      'rejection_reason', NEW.rejection_reason
    )
  );
  RETURN NEW;
END;
$function$;

-- 2) Booking deletions: include owner details
CREATE OR REPLACE FUNCTION public.audit_booking_deleted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_room TEXT;
  v_owner_email TEXT;
BEGIN
  IF v_actor IS NULL THEN RETURN OLD; END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = OLD.room_id;
  v_owner_email := public.get_actor_email(OLD.user_id);

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    'booking_deleted',
    'booking',
    OLD.id,
    'Deleted "' || OLD.title || '" booked by ' || COALESCE(v_owner_email, 'unknown') ||
    ' (' || COALESCE(v_room, 'room') || ' on ' || OLD.date ||
    ' ' || to_char(OLD.start_time, 'HH24:MI') || '–' || to_char(OLD.end_time, 'HH24:MI') || ')',
    jsonb_build_object(
      'title', OLD.title,
      'room_name', v_room,
      'date', OLD.date,
      'start_time', OLD.start_time::text,
      'end_time', OLD.end_time::text,
      'owner_id', OLD.user_id,
      'owner_email', v_owner_email,
      'last_status', OLD.status
    )
  );
  RETURN OLD;
END;
$function$;

-- 3) Booking creation audit
CREATE OR REPLACE FUNCTION public.audit_booking_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_room TEXT;
  v_owner_email TEXT;
BEGIN
  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
  v_owner_email := public.get_actor_email(NEW.user_id);

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    NEW.user_id,
    v_owner_email,
    'booking_created',
    'booking',
    NEW.id,
    'Created "' || NEW.title || '" (' || COALESCE(v_room, 'room') || ' on ' || NEW.date ||
    ' ' || to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') || ')',
    jsonb_build_object(
      'room_name', v_room,
      'date', NEW.date,
      'start_time', NEW.start_time::text,
      'end_time', NEW.end_time::text,
      'status', NEW.status,
      'owner_email', v_owner_email
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_audit_booking_created ON public.bookings;
CREATE TRIGGER trg_audit_booking_created
AFTER INSERT ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.audit_booking_created();

-- 4) Blocked slot modifications
CREATE OR REPLACE FUNCTION public.audit_slot_modified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_old_room TEXT;
  v_new_room TEXT;
  v_changes TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF NEW.room_id = OLD.room_id AND NEW.date = OLD.date
     AND NEW.start_time = OLD.start_time AND NEW.end_time = OLD.end_time
     AND COALESCE(NEW.reason,'') = COALESCE(OLD.reason,'') THEN
    RETURN NEW;
  END IF;

  IF NEW.room_id <> OLD.room_id THEN v_changes := array_append(v_changes, 'room'); END IF;
  IF NEW.date <> OLD.date THEN v_changes := array_append(v_changes, 'date'); END IF;
  IF NEW.start_time <> OLD.start_time OR NEW.end_time <> OLD.end_time THEN
    v_changes := array_append(v_changes, 'time'); END IF;
  IF COALESCE(NEW.reason,'') <> COALESCE(OLD.reason,'') THEN
    v_changes := array_append(v_changes, 'reason'); END IF;

  SELECT name INTO v_old_room FROM public.rooms WHERE id = OLD.room_id;
  SELECT name INTO v_new_room FROM public.rooms WHERE id = NEW.room_id;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    'slot_block_modified',
    'blocked_slot',
    NEW.id,
    'Modified blocked slot (' || array_to_string(v_changes, ', ') || ') — ' ||
    COALESCE(v_new_room, 'room') || ' on ' || NEW.date || ' ' ||
    to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI'),
    jsonb_build_object(
      'changed_fields', v_changes,
      'before', jsonb_build_object('room', v_old_room, 'date', OLD.date,
        'start_time', OLD.start_time::text, 'end_time', OLD.end_time::text, 'reason', OLD.reason),
      'after', jsonb_build_object('room', v_new_room, 'date', NEW.date,
        'start_time', NEW.start_time::text, 'end_time', NEW.end_time::text, 'reason', NEW.reason)
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_audit_slot_modified ON public.blocked_slots;
CREATE TRIGGER trg_audit_slot_modified
AFTER UPDATE ON public.blocked_slots
FOR EACH ROW EXECUTE FUNCTION public.audit_slot_modified();

-- 5) Room changes
CREATE OR REPLACE FUNCTION public.audit_room_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
    VALUES (v_actor, public.get_actor_email(v_actor), 'room_created', 'room', NEW.id,
      'Added room "' || NEW.name || '"',
      jsonb_build_object('name', NEW.name, 'capacity', NEW.capacity, 'min_members', NEW.min_members));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.name = OLD.name AND NEW.capacity = OLD.capacity AND NEW.min_members = OLD.min_members
       AND COALESCE(NEW.location,'') = COALESCE(OLD.location,'')
       AND COALESCE(NEW.description,'') = COALESCE(OLD.description,'') THEN
      RETURN NEW;
    END IF;
    INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
    VALUES (v_actor, public.get_actor_email(v_actor), 'room_updated', 'room', NEW.id,
      'Updated room "' || NEW.name || '"',
      jsonb_build_object(
        'before', jsonb_build_object('name', OLD.name, 'capacity', OLD.capacity,
          'min_members', OLD.min_members, 'location', OLD.location, 'description', OLD.description),
        'after', jsonb_build_object('name', NEW.name, 'capacity', NEW.capacity,
          'min_members', NEW.min_members, 'location', NEW.location, 'description', NEW.description)));
    RETURN NEW;
  ELSE
    INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
    VALUES (v_actor, public.get_actor_email(v_actor), 'room_deleted', 'room', OLD.id,
      'Removed room "' || OLD.name || '"',
      jsonb_build_object('name', OLD.name, 'capacity', OLD.capacity));
    RETURN OLD;
  END IF;
END;
$function$;

DROP TRIGGER IF EXISTS trg_audit_room_change ON public.rooms;
CREATE TRIGGER trg_audit_room_change
AFTER INSERT OR UPDATE OR DELETE ON public.rooms
FOR EACH ROW EXECUTE FUNCTION public.audit_room_change();

-- 6) Member invite responses
CREATE OR REPLACE FUNCTION public.audit_member_response()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor UUID := auth.uid();
  v_booking RECORD;
  v_room TEXT;
BEGIN
  IF NEW.status = OLD.status OR NEW.status NOT IN ('accepted', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT b.title, b.date, b.start_time, b.end_time, b.room_id, b.user_id
    INTO v_booking FROM public.bookings b WHERE b.id = NEW.booking_id;
  SELECT name INTO v_room FROM public.rooms WHERE id = v_booking.room_id;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    NEW.email,
    'invite_' || NEW.status,
    'booking',
    NEW.booking_id,
    NEW.email || ' ' || NEW.status || ' the invite for "' || COALESCE(v_booking.title, 'booking') ||
    '" (' || COALESCE(v_room, 'room') || ' on ' || COALESCE(v_booking.date::text, '?') || ')',
    jsonb_build_object(
      'member_email', NEW.email,
      'member_status', NEW.status,
      'booking_owner', public.get_actor_email(v_booking.user_id),
      'room_name', v_room
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_audit_member_response ON public.booking_members;
CREATE TRIGGER trg_audit_member_response
AFTER UPDATE ON public.booking_members
FOR EACH ROW EXECUTE FUNCTION public.audit_member_response();

REVOKE ALL ON FUNCTION public.audit_booking_created() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_slot_modified() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_room_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_member_response() FROM PUBLIC, anon, authenticated;
