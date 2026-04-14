
-- Create app_role enum
CREATE TYPE public.app_role AS ENUM ('admin', 'user');

-- Create profiles table
CREATE TABLE public.profiles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all profiles" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Create user_roles table
CREATE TABLE public.user_roles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'user',
  UNIQUE(user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Security definer function for role checks
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins can view all roles" ON public.user_roles FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can manage roles" ON public.user_roles FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

-- Create rooms table
CREATE TABLE public.rooms (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  capacity INT NOT NULL DEFAULT 4,
  min_members INT NOT NULL DEFAULT 3,
  location TEXT,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view rooms" ON public.rooms FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage rooms" ON public.rooms FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

-- Seed rooms
INSERT INTO public.rooms (name, capacity, min_members, location, description) VALUES
  ('MR-1', 6, 2, 'Ground Floor', 'Meeting Room 1 - Small meetings'),
  ('Rumi', 10, 3, 'First Floor', 'Rumi Conference Room'),
  ('Chanakya', 12, 3, 'First Floor', 'Chanakya Conference Room'),
  ('Frida', 8, 3, 'Second Floor', 'Frida Meeting Room');

-- Create bookings table
CREATE TABLE public.bookings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending_members' CHECK (status IN ('pending_members', 'pending_admin', 'approved', 'rejected', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT valid_time CHECK (end_time > start_time)
);

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view approved bookings" ON public.bookings FOR SELECT TO authenticated
  USING (status = 'approved' OR user_id = auth.uid());
CREATE POLICY "Admins can view all bookings" ON public.bookings FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Users can create bookings" ON public.bookings FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own bookings" ON public.bookings FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Admins can update any booking" ON public.bookings FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Users can delete own bookings" ON public.bookings FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- Create booking_members table
CREATE TABLE public.booking_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(booking_id, email)
);

ALTER TABLE public.booking_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view members of their bookings" ON public.booking_members FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.bookings b WHERE b.id = booking_id AND b.user_id = auth.uid()));
CREATE POLICY "Users can view their own memberships" ON public.booking_members FOR SELECT TO authenticated
  USING (email IN (SELECT email FROM public.profiles WHERE user_id = auth.uid()));
CREATE POLICY "Admins can view all members" ON public.booking_members FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Booking owners can insert members" ON public.booking_members FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.bookings b WHERE b.id = booking_id AND b.user_id = auth.uid()));
CREATE POLICY "Members can update own status" ON public.booking_members FOR UPDATE TO authenticated
  USING (email IN (SELECT email FROM public.profiles WHERE user_id = auth.uid()));

-- Admin blocked slots
CREATE TABLE public.blocked_slots (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  reason TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT valid_blocked_time CHECK (end_time > start_time)
);

ALTER TABLE public.blocked_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view blocked slots" ON public.blocked_slots FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage blocked slots" ON public.blocked_slots FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

-- Trigger to auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to check booking conflicts
CREATE OR REPLACE FUNCTION public.check_booking_conflict(
  p_room_id UUID,
  p_date DATE,
  p_start_time TIME,
  p_end_time TIME,
  p_exclude_booking_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookings
    WHERE room_id = p_room_id
      AND date = p_date
      AND status IN ('approved', 'pending_admin', 'pending_members')
      AND (p_exclude_booking_id IS NULL OR id != p_exclude_booking_id)
      AND start_time < p_end_time
      AND end_time > p_start_time
  )
$$;

-- Function to check user daily hours
CREATE OR REPLACE FUNCTION public.get_user_daily_hours(
  p_user_id UUID,
  p_date DATE,
  p_exclude_booking_id UUID DEFAULT NULL
)
RETURNS INTERVAL
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(end_time - start_time), INTERVAL '0 hours')
  FROM public.bookings
  WHERE user_id = p_user_id
    AND date = p_date
    AND status IN ('approved', 'pending_admin', 'pending_members')
    AND (p_exclude_booking_id IS NULL OR id != p_exclude_booking_id)
$$;

-- Function to check user time overlap across rooms
CREATE OR REPLACE FUNCTION public.check_user_time_overlap(
  p_user_id UUID,
  p_date DATE,
  p_start_time TIME,
  p_end_time TIME,
  p_exclude_booking_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookings b
    WHERE b.date = p_date
      AND b.status IN ('approved', 'pending_admin', 'pending_members')
      AND (p_exclude_booking_id IS NULL OR b.id != p_exclude_booking_id)
      AND b.start_time < p_end_time
      AND b.end_time > p_start_time
      AND (
        b.user_id = p_user_id
        OR EXISTS (
          SELECT 1 FROM public.booking_members bm
          WHERE bm.booking_id = b.id
            AND bm.email IN (SELECT email FROM public.profiles WHERE user_id = p_user_id)
            AND bm.status != 'rejected'
        )
      )
  )
$$;

-- Function to check blocked slots
CREATE OR REPLACE FUNCTION public.check_blocked_slot(
  p_room_id UUID,
  p_date DATE,
  p_start_time TIME,
  p_end_time TIME
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_slots
    WHERE room_id = p_room_id
      AND date = p_date
      AND start_time < p_end_time
      AND end_time > p_start_time
  )
$$;
