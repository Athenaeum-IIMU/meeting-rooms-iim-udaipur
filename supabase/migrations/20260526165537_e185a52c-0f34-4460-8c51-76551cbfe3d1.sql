
-- 1. Enforce @iimu.ac.in email domain on profiles
CREATE OR REPLACE FUNCTION public.enforce_iimu_email_domain()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF LOWER(NEW.email) NOT LIKE '%@iimu.ac.in' THEN
    RAISE EXCEPTION 'Only @iimu.ac.in email addresses are allowed (got %)', NEW.email;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS enforce_iimu_email_profiles ON public.profiles;
CREATE TRIGGER enforce_iimu_email_profiles
BEFORE INSERT OR UPDATE OF email ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_iimu_email_domain();

-- 2. Enforce @iimu.ac.in email on booking_members invites
CREATE OR REPLACE FUNCTION public.enforce_iimu_email_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF LOWER(NEW.email) NOT LIKE '%@iimu.ac.in' THEN
    RAISE EXCEPTION 'Only @iimu.ac.in members can be invited (got %)', NEW.email;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS enforce_iimu_email_members ON public.booking_members;
CREATE TRIGGER enforce_iimu_email_members
BEFORE INSERT OR UPDATE OF email ON public.booking_members
FOR EACH ROW EXECUTE FUNCTION public.enforce_iimu_email_member();

-- 3. Members can see bookings they're invited to (any status, not just approved)
DROP POLICY IF EXISTS "Members can view their bookings" ON public.bookings;
CREATE POLICY "Members can view their bookings"
ON public.bookings FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.booking_members bm
    WHERE bm.booking_id = bookings.id
      AND (
        bm.user_id = auth.uid()
        OR LOWER(bm.email) = LOWER(
          (SELECT email FROM public.profiles WHERE user_id = auth.uid() LIMIT 1)
        )
      )
  )
);

-- 4. Members can see their own membership rows even before user_id is linked (by email)
DROP POLICY IF EXISTS "Users can view invites by email" ON public.booking_members;
CREATE POLICY "Users can view invites by email"
ON public.booking_members FOR SELECT
TO authenticated
USING (
  LOWER(email) = LOWER(
    (SELECT email FROM public.profiles WHERE user_id = auth.uid() LIMIT 1)
  )
);

-- 5. Add realtime publication for live calendar updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE public.blocked_slots;
ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_members;
