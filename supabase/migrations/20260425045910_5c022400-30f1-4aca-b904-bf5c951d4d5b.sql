
-- =============================================================
-- NOTIFICATIONS SYSTEM
-- =============================================================
CREATE TABLE public.notifications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  booking_id UUID,
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user_unread
  ON public.notifications (user_id, read, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own notifications"
  ON public.notifications FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users update own notifications"
  ON public.notifications FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users delete own notifications"
  ON public.notifications FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- Service-role / triggers always bypass RLS; we also allow inserts from
-- authenticated users so client-side flows (member responses, admin
-- approvals) can write notification rows for OTHER users.
CREATE POLICY "Authenticated can create notifications"
  ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- =============================================================
-- HELPER FUNCTION: notify a user by email (resolves to user_id)
-- =============================================================
CREATE OR REPLACE FUNCTION public.notify_user_by_email(
  p_email TEXT,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_booking_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT user_id INTO v_user_id
  FROM public.profiles
  WHERE LOWER(email) = LOWER(p_email)
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_user_id, p_type, p_title, p_body, p_booking_id);
  END IF;
END;
$$;

-- =============================================================
-- TRIGGER: when booking_members row inserted -> notify the invitee
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_booking_member_invite()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_room_name TEXT;
  v_organizer TEXT;
BEGIN
  SELECT b.id, b.title, b.date, b.start_time, b.end_time, b.user_id, r.name AS room_name
  INTO v_booking
  FROM public.bookings b
  LEFT JOIN public.rooms r ON r.id = b.room_id
  WHERE b.id = NEW.booking_id;

  SELECT COALESCE(full_name, email) INTO v_organizer
  FROM public.profiles WHERE user_id = v_booking.user_id;

  PERFORM public.notify_user_by_email(
    NEW.email,
    'invite',
    'You''ve been invited to a meeting',
    COALESCE(v_organizer, 'Someone') || ' invited you to "' || v_booking.title ||
    '" in ' || COALESCE(v_booking.room_name, 'a room') ||
    ' on ' || v_booking.date ||
    ' at ' || to_char(v_booking.start_time, 'HH24:MI') ||
    '–' || to_char(v_booking.end_time, 'HH24:MI'),
    NEW.booking_id
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_booking_member_invite
AFTER INSERT ON public.booking_members
FOR EACH ROW EXECUTE FUNCTION public.handle_booking_member_invite();

-- =============================================================
-- TRIGGER: when booking_members status changes -> notify organizer
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_booking_member_response()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_responder TEXT;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('accepted', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT b.id, b.title, b.date, b.user_id, r.name AS room_name
  INTO v_booking
  FROM public.bookings b
  LEFT JOIN public.rooms r ON r.id = b.room_id
  WHERE b.id = NEW.booking_id;

  v_responder := NEW.email;

  INSERT INTO public.notifications (user_id, type, title, body, booking_id)
  VALUES (
    v_booking.user_id,
    'member_response',
    CASE WHEN NEW.status = 'accepted'
      THEN v_responder || ' accepted your invite'
      ELSE v_responder || ' declined your invite' END,
    'For "' || v_booking.title || '" in ' || COALESCE(v_booking.room_name, 'room') ||
    ' on ' || v_booking.date ||
    CASE WHEN NEW.status = 'rejected'
      THEN '. Your booking has been cancelled.'
      ELSE '.' END,
    NEW.booking_id
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_booking_member_response
AFTER UPDATE ON public.booking_members
FOR EACH ROW EXECUTE FUNCTION public.handle_booking_member_response();

-- =============================================================
-- TRIGGER: when bookings.status changes -> notify owner + accepted members
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_booking_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_name TEXT;
  v_title TEXT;
  v_body TEXT;
  v_member RECORD;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  -- Only notify on terminal states or admin transitions
  IF NEW.status NOT IN ('approved', 'rejected', 'cancelled') THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = NEW.room_id;

  v_title := CASE NEW.status
    WHEN 'approved' THEN 'Booking approved ✓'
    WHEN 'rejected' THEN 'Booking rejected'
    WHEN 'cancelled' THEN 'Booking cancelled'
  END;

  v_body := '"' || NEW.title || '" — ' || COALESCE(v_room_name, 'room') ||
            ' on ' || NEW.date || ' at ' ||
            to_char(NEW.start_time, 'HH24:MI') || '–' ||
            to_char(NEW.end_time, 'HH24:MI');

  -- Notify owner
  INSERT INTO public.notifications (user_id, type, title, body, booking_id)
  VALUES (NEW.user_id, 'booking_' || NEW.status, v_title, v_body, NEW.id);

  -- Notify accepted members
  FOR v_member IN
    SELECT email FROM public.booking_members
    WHERE booking_id = NEW.id AND status = 'accepted'
  LOOP
    PERFORM public.notify_user_by_email(
      v_member.email,
      'booking_' || NEW.status,
      v_title,
      v_body,
      NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_booking_status_change
AFTER UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.handle_booking_status_change();

-- =============================================================
-- TRIGGER: when admin modifies a booking (date/time/room) -> notify
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_booking_modified()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_name TEXT;
  v_body TEXT;
  v_member RECORD;
BEGIN
  -- Only fire when scheduling fields change (not status)
  IF NEW.date = OLD.date
     AND NEW.start_time = OLD.start_time
     AND NEW.end_time = OLD.end_time
     AND NEW.room_id = OLD.room_id
     AND NEW.title = OLD.title
     AND NEW.user_id = OLD.user_id THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = NEW.room_id;

  v_body := 'Updated to "' || NEW.title || '" in ' || COALESCE(v_room_name, 'room') ||
            ' on ' || NEW.date || ' at ' ||
            to_char(NEW.start_time, 'HH24:MI') || '–' ||
            to_char(NEW.end_time, 'HH24:MI');

  INSERT INTO public.notifications (user_id, type, title, body, booking_id)
  VALUES (NEW.user_id, 'booking_modified', 'Your booking was modified by admin', v_body, NEW.id);

  -- If owner changed, also notify the previous owner
  IF NEW.user_id <> OLD.user_id THEN
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (OLD.user_id, 'booking_modified', 'Booking ownership transferred',
            'A booking you created was reassigned by admin: ' || v_body, NEW.id);
  END IF;

  FOR v_member IN
    SELECT email FROM public.booking_members
    WHERE booking_id = NEW.id AND status IN ('accepted', 'pending')
  LOOP
    PERFORM public.notify_user_by_email(
      v_member.email,
      'booking_modified',
      'A meeting you''re part of was modified',
      v_body,
      NEW.id
    );
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_booking_modified
AFTER UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.handle_booking_modified();

-- =============================================================
-- TRIGGER: when admin blocks a slot -> notify affected bookings
-- (the cancellation trigger above also fires; this adds context)
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_slot_blocked()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_name TEXT;
  v_booking RECORD;
  v_member RECORD;
  v_body TEXT;
BEGIN
  SELECT name INTO v_room_name FROM public.rooms WHERE id = NEW.room_id;

  FOR v_booking IN
    SELECT id, user_id, title, date, start_time, end_time
    FROM public.bookings
    WHERE room_id = NEW.room_id
      AND date = NEW.date
      AND status IN ('approved', 'pending_admin', 'pending_members', 'cancelled')
      AND start_time < NEW.end_time
      AND end_time > NEW.start_time
  LOOP
    v_body := 'Admin blocked ' || COALESCE(v_room_name, 'this room') ||
              ' on ' || NEW.date || ' (' ||
              to_char(NEW.start_time, 'HH24:MI') || '–' ||
              to_char(NEW.end_time, 'HH24:MI') || ')' ||
              CASE WHEN NEW.reason IS NOT NULL THEN ' — ' || NEW.reason ELSE '' END ||
              '. Your booking "' || v_booking.title || '" has been cancelled.';

    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_booking.user_id, 'slot_blocked', 'Slot blocked by admin', v_body, v_booking.id);

    FOR v_member IN
      SELECT email FROM public.booking_members
      WHERE booking_id = v_booking.id AND status = 'accepted'
    LOOP
      PERFORM public.notify_user_by_email(
        v_member.email,
        'slot_blocked',
        'Slot blocked by admin',
        v_body,
        v_booking.id
      );
    END LOOP;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_slot_blocked
AFTER INSERT ON public.blocked_slots
FOR EACH ROW EXECUTE FUNCTION public.handle_slot_blocked();

-- =============================================================
-- VALIDATION TRIGGER: enforce max 2 days advance booking server-side
-- (skip for admin actions: they can edit anytime)
-- =============================================================
CREATE OR REPLACE FUNCTION public.validate_booking_date()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Allow admins to bypass on UPDATE
  IF TG_OP = 'UPDATE' AND public.has_role(auth.uid(), 'admin') THEN
    RETURN NEW;
  END IF;

  IF NEW.date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot book a date in the past';
  END IF;

  IF NEW.date > CURRENT_DATE + INTERVAL '2 days' THEN
    RAISE EXCEPTION 'Cannot book more than 2 days in advance';
  END IF;

  IF NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'End time must be after start time';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_booking_date
BEFORE INSERT ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.validate_booking_date();
