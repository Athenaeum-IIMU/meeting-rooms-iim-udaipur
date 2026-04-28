-- Re-assert realtime.messages SELECT policy: strictly user-scoped topics only.
-- Topics MUST end with ':<auth.uid()>'. No public:%, no wildcard bypass.
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT polname FROM pg_policy
    WHERE polrelid = 'realtime.messages'::regclass
      AND polcmd = 'r'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON realtime.messages', pol.polname);
  END LOOP;
END $$;

CREATE POLICY "Authenticated users subscribe to own user-scoped topics only"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.topic() IS NOT NULL
  AND realtime.topic() LIKE '%:' || auth.uid()::text
);