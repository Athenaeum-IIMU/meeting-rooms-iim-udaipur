
-- 1) Audit role changes on user_roles
CREATE OR REPLACE FUNCTION public.audit_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_target UUID;
  v_role TEXT;
  v_action TEXT;
  v_target_email TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_target := NEW.user_id;
    v_role := NEW.role::text;
    v_action := 'role_granted';
  ELSIF TG_OP = 'DELETE' THEN
    v_target := OLD.user_id;
    v_role := OLD.role::text;
    v_action := 'role_revoked';
  ELSE
    RETURN NULL;
  END IF;

  SELECT email INTO v_target_email FROM public.profiles WHERE user_id = v_target LIMIT 1;

  INSERT INTO public.audit_log (actor_id, actor_email, action, target_type, target_id, summary, details)
  VALUES (
    v_actor,
    public.get_actor_email(v_actor),
    v_action,
    'user_role',
    v_target,
    CASE WHEN TG_OP = 'INSERT'
      THEN 'Granted role "' || v_role || '" to ' || COALESCE(v_target_email, v_target::text)
      ELSE 'Revoked role "' || v_role || '" from ' || COALESCE(v_target_email, v_target::text)
    END,
    jsonb_build_object('role', v_role, 'target_email', v_target_email)
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.audit_role_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_audit_role_change_ins ON public.user_roles;
DROP TRIGGER IF EXISTS trg_audit_role_change_del ON public.user_roles;

CREATE TRIGGER trg_audit_role_change_ins
AFTER INSERT ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.audit_role_change();

CREATE TRIGGER trg_audit_role_change_del
AFTER DELETE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.audit_role_change();

-- 2) Stop broadcasting booking_members through realtime so member emails
-- cannot be received by unrelated authenticated users via the realtime channel.
-- The UI will still refresh via bookings/blocked_slots realtime events and
-- on-demand fetches; member rows are protected by existing RLS for direct reads.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'booking_members'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime DROP TABLE public.booking_members';
  END IF;
END $$;
