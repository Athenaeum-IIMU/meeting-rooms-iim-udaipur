-- Replace the realtime.messages SELECT policy to remove the public:% bypass.
-- Only allow authenticated users to subscribe to topics ending with their own UID.
DROP POLICY IF EXISTS "Authenticated users can read own topic" ON realtime.messages;
DROP POLICY IF EXISTS "Authenticated can read own topic" ON realtime.messages;
DROP POLICY IF EXISTS "auth read own topic" ON realtime.messages;
DROP POLICY IF EXISTS "Users can read their own realtime topics" ON realtime.messages;

CREATE POLICY "Users can read their own realtime topics"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.topic() LIKE '%:' || auth.uid()::text
);