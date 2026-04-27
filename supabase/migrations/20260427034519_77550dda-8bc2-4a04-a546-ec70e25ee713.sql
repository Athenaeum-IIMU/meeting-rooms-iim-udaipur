CREATE TABLE public.waitlist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, room_id, date, start_time, end_time)
);

CREATE INDEX idx_waitlist_lookup ON public.waitlist(room_id, date);

ALTER TABLE public.waitlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own waitlist"
  ON public.waitlist FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Admins view all waitlist"
  ON public.waitlist FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users insert own waitlist"
  ON public.waitlist FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users delete own waitlist"
  ON public.waitlist FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- Validation: same date/time rules as bookings
CREATE OR REPLACE FUNCTION public.validate_waitlist_entry()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot waitlist a date in the past';
  END IF;
  IF NEW.date > CURRENT_DATE + INTERVAL '2 days' THEN
    RAISE EXCEPTION 'Cannot waitlist more than 2 days in advance';
  END IF;
  IF NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'End time must be after start time';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_waitlist
BEFORE INSERT ON public.waitlist
FOR EACH ROW EXECUTE FUNCTION public.validate_waitlist_entry();

-- Notify waitlist when a booking frees up
CREATE OR REPLACE FUNCTION public.notify_waitlist_on_freed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_room TEXT;
  v_entry RECORD;
BEGIN
  -- Only act when transitioning into a freeing state
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('cancelled', 'rejected') THEN RETURN NEW; END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;

  FOR v_entry IN
    SELECT id, user_id, start_time, end_time
    FROM public.waitlist
    WHERE room_id = NEW.room_id
      AND date = NEW.date
      AND start_time < NEW.end_time
      AND end_time > NEW.start_time
  LOOP
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (
      v_entry.user_id,
      'waitlist_freed',
      'A slot you waitlisted just opened up',
      COALESCE(v_room, 'A room') || ' is now free on ' || NEW.date ||
      ' (' || to_char(NEW.start_time, 'HH24:MI') || '–' ||
      to_char(NEW.end_time, 'HH24:MI') || '). Book it before someone else does!',
      NEW.id
    );
    -- Remove the waitlist entry now that they've been notified
    DELETE FROM public.waitlist WHERE id = v_entry.id;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_waitlist_on_freed
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.notify_waitlist_on_freed();