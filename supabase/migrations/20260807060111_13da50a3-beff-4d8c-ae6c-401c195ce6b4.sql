DROP POLICY IF EXISTS "Admins can delete any booking" ON public.bookings;
CREATE POLICY "Admins can delete any booking"
ON public.bookings FOR DELETE TO authenticated
USING (private.has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Admins can delete booking members" ON public.booking_members;
CREATE POLICY "Admins can delete booking members"
ON public.booking_members FOR DELETE TO authenticated
USING (private.has_role(auth.uid(), 'admin'::app_role));