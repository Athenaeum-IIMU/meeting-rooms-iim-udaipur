
CREATE POLICY "Admins can manage all members"
  ON public.booking_members FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));
