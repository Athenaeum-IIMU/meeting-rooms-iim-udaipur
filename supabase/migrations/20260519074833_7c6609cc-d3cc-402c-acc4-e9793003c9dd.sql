
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.send_notification_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_email TEXT;
  v_url TEXT := 'https://sjmnthisxaqmvdtgiuso.supabase.co/functions/v1/send-email';
  v_html TEXT;
BEGIN
  SELECT email INTO v_email FROM public.profiles WHERE user_id = NEW.user_id LIMIT 1;
  IF v_email IS NULL OR v_email = '' THEN
    RETURN NEW;
  END IF;

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
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object(
      'to', v_email,
      'subject', NEW.title,
      'html', v_html,
      'text', NEW.title || E'\n\n' || NEW.body
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- never block notification inserts if email fails
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_send_notification_email ON public.notifications;
CREATE TRIGGER trg_send_notification_email
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.send_notification_email();
