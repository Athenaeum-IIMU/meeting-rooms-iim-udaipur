-- 1) Drop blocked_slots from realtime publication; client will poll instead.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'blocked_slots'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime DROP TABLE public.blocked_slots';
  END IF;
END $$;

-- 2) Restrict shares_booking() to active bookings only.
CREATE OR REPLACE FUNCTION private.shares_booking(_viewer uuid, _target uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    JOIN public.profiles p ON LOWER(p.email) = LOWER(bm.email)
    WHERE b.user_id = _viewer
      AND p.user_id = _target
      AND b.status IN ('approved', 'pending_admin', 'pending_members', 'needs_replacement')
      AND b.date >= CURRENT_DATE
      AND bm.status IN ('pending', 'accepted')
    UNION ALL
    SELECT 1
    FROM public.bookings b
    JOIN public.booking_members bm ON bm.booking_id = b.id
    JOIN public.profiles p ON LOWER(p.email) = LOWER(bm.email)
    WHERE b.user_id = _target
      AND p.user_id = _viewer
      AND b.status IN ('approved', 'pending_admin', 'pending_members', 'needs_replacement')
      AND b.date >= CURRENT_DATE
      AND bm.status IN ('pending', 'accepted')
  )
$$;
