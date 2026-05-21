
CREATE OR REPLACE FUNCTION public.send_notification_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_email TEXT;
  v_url TEXT := 'https://olvjcbfdzqwkanaavftq.supabase.co/functions/v1/send-email';
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
    ),
    timeout_milliseconds := 30000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;
