ALTER TABLE public.bookings REPLICA IDENTITY FULL;
ALTER TABLE public.booking_members REPLICA IDENTITY FULL;
ALTER TABLE public.blocked_slots REPLICA IDENTITY FULL;

ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.blocked_slots;