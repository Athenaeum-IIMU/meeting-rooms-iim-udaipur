ALTER TABLE public.bookings
DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE public.bookings
ADD CONSTRAINT bookings_status_check
CHECK (status IN ('pending_members', 'pending_admin', 'approved', 'rejected', 'cancelled', 'needs_replacement'));