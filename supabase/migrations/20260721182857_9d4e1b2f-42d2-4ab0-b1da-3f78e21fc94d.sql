CREATE INDEX IF NOT EXISTS idx_booking_members_email_lower_status ON public.booking_members (lower(email), status);
CREATE INDEX IF NOT EXISTS idx_blocked_slots_date ON public.blocked_slots (date);
CREATE INDEX IF NOT EXISTS idx_booking_attempts_success_created ON public.booking_attempts (success, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at ON public.bookings (created_at DESC);