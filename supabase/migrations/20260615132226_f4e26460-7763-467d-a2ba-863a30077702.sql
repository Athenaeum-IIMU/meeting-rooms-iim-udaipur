CREATE OR REPLACE FUNCTION public.filter_unregistered_emails(p_emails text[])
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(e ORDER BY e), ARRAY[]::text[])
  FROM (
    SELECT lower(trim(unnest(p_emails))) AS e
  ) src
  WHERE NOT EXISTS (
    SELECT 1 FROM public.profiles p WHERE lower(p.email) = src.e
  );
$$;

GRANT EXECUTE ON FUNCTION public.filter_unregistered_emails(text[]) TO authenticated;