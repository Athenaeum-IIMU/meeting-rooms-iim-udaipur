
CREATE OR REPLACE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_current_user_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_current_user_admin() TO authenticated, service_role;
