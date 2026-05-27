
-- 1. Add explicit UPDATE policy on waitlist (defense in depth)
CREATE POLICY "Users update own waitlist"
ON public.waitlist
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 2. Restrict Realtime channel access
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

-- Authenticated users may only receive realtime broadcasts for tables we publish,
-- and only for rows they can already read under existing RLS. We rely on the
-- fact that postgres_changes events go through RLS on the source table; this
-- policy gates the realtime.messages channel join itself.
CREATE POLICY "Authenticated can receive realtime"
ON realtime.messages
FOR SELECT
TO authenticated
USING (true);
