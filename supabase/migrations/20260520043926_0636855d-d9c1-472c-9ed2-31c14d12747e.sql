
-- 1. Ensure vault is available and create an internal shared secret for send-email
DO $$
DECLARE
  v_exists boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'send_email_secret') INTO v_exists;
  IF NOT v_exists THEN
    PERFORM vault.create_secret(encode(gen_random_bytes(32), 'hex'), 'send_email_secret');
  END IF;
END$$;

-- 2. Helper to read the secret; restricted to service_role only
CREATE OR REPLACE FUNCTION public.get_send_email_secret()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, vault
AS $$
  SELECT decrypted_secret
  FROM vault.decrypted_secrets
  WHERE name = 'send_email_secret'
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_send_email_secret() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_send_email_secret() TO service_role;

-- 3. Update the notification email trigger to authenticate calls with the secret
CREATE OR REPLACE FUNCTION public.send_notification_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_email TEXT;
  v_url TEXT := 'https://sjmnthisxaqmvdtgiuso.supabase.co/functions/v1/send-email';
  v_html TEXT;
  v_secret TEXT;
BEGIN
  SELECT email INTO v_email FROM public.profiles WHERE user_id = NEW.user_id LIMIT 1;
  IF v_email IS NULL OR v_email = '' THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'send_email_secret' LIMIT 1;

  v_html := '<div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">'
          || '<div style="background:#2563EB;color:#fff;padding:16px 20px;border-radius:8px 8px 0 0;">'
          || '<h2 style="margin:0;font-size:18px;">IIMU Meeting Rooms</h2></div>'
          || '<div style="border:1px solid #e5e7eb;border-top:none;padding:20px;border-radius:0 0 8px 8px;background:#fff;">'
          || '<h3 style="margin:0 0 12px;color:#111827;font-size:16px;">' || replace(NEW.title, '<','&lt;') || '</h3>'
          || '<p style="margin:0;color:#374151;font-size:14px;white-space:pre-line;line-height:1.5;">' || replace(NEW.body, '<','&lt;') || '</p>'
          || '<p style="margin-top:24px;font-size:12px;color:#6b7280;">Open the scheduler: '
          || '<a href="https://meeting-rooms-iim-udaipur.lovable.app/my-bookings" style="color:#2563EB;">View in app</a></p>'
          || '</div></div>';

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-send-email-secret', COALESCE(v_secret, '')
    ),
    body := jsonb_build_object(
      'to', v_email,
      'subject', NEW.title,
      'html', v_html,
      'text', NEW.title || E'\n\n' || NEW.body
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;

-- 4. Revoke EXECUTE from anon on all SECURITY DEFINER functions in public schema.
-- Authenticated keeps access (needed for RLS-referenced functions like has_role/shares_booking).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC, anon;',
                   r.nspname, r.proname, r.args);
  END LOOP;
END$$;
