-- Audit log table
CREATE TABLE public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_id UUID,
  actor_email TEXT,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id UUID,
  summary TEXT NOT NULL,
  details JSONB
);

CREATE INDEX idx_audit_log_created ON public.audit_log(created_at DESC);
CREATE INDEX idx_audit_log_target ON public.audit_log(target_type, target_id);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view audit log"
  ON public.audit_log FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- No INSERT/UPDATE/DELETE policies → only SECURITY DEFINER triggers can write

-- Helper to get actor email
CREATE OR REPLACE FUNCTION public.get_actor_email(_user_id UUID)
RETURNS TEXT
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT email FROM public.profiles WHERE user_id = _user_id LIMIT 1;
$$;

-- Trigger: log booking status changes (approve/reject/cancel)
CREATE OR REPLACE FUNCTION public.audit_booking_status_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_room TEXT;
  v_action TEXT;
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('approved', 'rejected', 'cancelled') THEN RETURN NEW; END IF;

  -- Only log if an admin (not the owner self-cancelling) made the change
  IF NOT public.has_role(v_actor, 'admin') THEN RETURN NEW; END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
  v_action := 'booking_' || NEW.status;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    v_action,
    'booking',
    NEW.id,
    'Set "' || NEW.title || '" (' || COALESCE(v_room, 'room') || ' on ' || NEW.date ||
    ' ' || to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') ||
    ') to ' || NEW.status,
    jsonb_build_object('from_status', OLD.status, 'to_status', NEW.status)
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_booking_status
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.audit_booking_status_change();

-- Trigger: log booking modifications (title/room/date/time/owner)
CREATE OR REPLACE FUNCTION public.audit_booking_modified()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_changes TEXT[] := ARRAY[]::TEXT[];
  v_old_room TEXT;
  v_new_room TEXT;
BEGIN
  IF NEW.date = OLD.date AND NEW.start_time = OLD.start_time
     AND NEW.end_time = OLD.end_time AND NEW.room_id = OLD.room_id
     AND NEW.title = OLD.title AND NEW.user_id = OLD.user_id THEN
    RETURN NEW;
  END IF;

  IF NOT public.has_role(v_actor, 'admin') THEN RETURN NEW; END IF;

  IF NEW.title <> OLD.title THEN v_changes := array_append(v_changes, 'title'); END IF;
  IF NEW.date <> OLD.date THEN v_changes := array_append(v_changes, 'date'); END IF;
  IF NEW.start_time <> OLD.start_time OR NEW.end_time <> OLD.end_time THEN
    v_changes := array_append(v_changes, 'time'); END IF;
  IF NEW.room_id <> OLD.room_id THEN v_changes := array_append(v_changes, 'room'); END IF;
  IF NEW.user_id <> OLD.user_id THEN v_changes := array_append(v_changes, 'owner'); END IF;

  SELECT name INTO v_old_room FROM public.rooms WHERE id = OLD.room_id;
  SELECT name INTO v_new_room FROM public.rooms WHERE id = NEW.room_id;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    'booking_modified',
    'booking',
    NEW.id,
    'Modified booking "' || NEW.title || '" (' || array_to_string(v_changes, ', ') || ')',
    jsonb_build_object(
      'changed_fields', v_changes,
      'before', jsonb_build_object(
        'title', OLD.title, 'date', OLD.date,
        'start_time', OLD.start_time::text, 'end_time', OLD.end_time::text,
        'room', v_old_room, 'owner_id', OLD.user_id
      ),
      'after', jsonb_build_object(
        'title', NEW.title, 'date', NEW.date,
        'start_time', NEW.start_time::text, 'end_time', NEW.end_time::text,
        'room', v_new_room, 'owner_id', NEW.user_id
      )
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_booking_modified
AFTER UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.audit_booking_modified();

-- Trigger: log slot blocks
CREATE OR REPLACE FUNCTION public.audit_slot_blocked()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_room TEXT;
BEGIN
  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    'slot_blocked',
    'blocked_slot',
    NEW.id,
    'Blocked ' || COALESCE(v_room, 'room') || ' on ' || NEW.date ||
    ' (' || to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') || ')' ||
    CASE WHEN NEW.reason IS NOT NULL THEN ' — ' || NEW.reason ELSE '' END,
    jsonb_build_object('reason', NEW.reason)
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_slot_blocked
AFTER INSERT ON public.blocked_slots
FOR EACH ROW EXECUTE FUNCTION public.audit_slot_blocked();

-- Trigger: log slot unblocks
CREATE OR REPLACE FUNCTION public.audit_slot_unblocked()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_room TEXT;
BEGIN
  SELECT name INTO v_room FROM public.rooms WHERE id = OLD.room_id;
  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    'slot_unblocked',
    'blocked_slot',
    OLD.id,
    'Unblocked ' || COALESCE(v_room, 'room') || ' on ' || OLD.date ||
    ' (' || to_char(OLD.start_time, 'HH24:MI') || '–' || to_char(OLD.end_time, 'HH24:MI') || ')',
    jsonb_build_object('reason', OLD.reason)
  );
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_audit_slot_unblocked
AFTER DELETE ON public.blocked_slots
FOR EACH ROW EXECUTE FUNCTION public.audit_slot_unblocked();