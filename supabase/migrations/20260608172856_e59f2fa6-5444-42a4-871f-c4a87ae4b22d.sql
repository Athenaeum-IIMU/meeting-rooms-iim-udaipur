
-- Allow booking_pending_admin notifications to trigger emails
CREATE OR REPLACE FUNCTION public.send_notification_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_email TEXT;
  v_url   TEXT := 'https://olvjcbfdzqwkanaavftq.supabase.co/functions/v1/send-email';
  v_html  TEXT;
  v_secret TEXT;
  v_title_safe TEXT;
  v_body_safe TEXT;
  v_allowed_types TEXT[] := ARRAY[
    'invite',
    'booking_approved',
    'booking_rejected',
    'booking_cancelled',
    'slot_blocked',
    'waitlist_freed',
    'waitlist_available',
    'reminder',
    'booking_pending_admin'
  ];
BEGIN
  IF NOT (NEW.type = ANY (v_allowed_types)) THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NOT NULL AND NEW.user_id = auth.uid() THEN
    RETURN NEW;
  END IF;

  SELECT email INTO v_email FROM public.profiles WHERE user_id = NEW.user_id LIMIT 1;
  IF v_email IS NULL OR v_email = '' THEN
    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, error, booking_id, notification_id)
    VALUES (NEW.user_id, '(missing)', NEW.title, 'failed', 'No email on profile', NEW.booking_id, NEW.id);
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'send_email_secret' LIMIT 1;

  v_title_safe := replace(replace(replace(replace(replace(COALESCE(NEW.title,''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
  v_body_safe := replace(replace(replace(replace(replace(COALESCE(NEW.body,''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');

  v_html := '<div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">'
          || '<div style="background:#2563EB;color:#fff;padding:16px 20px;border-radius:8px 8px 0 0;">'
          || '<h2 style="margin:0;font-size:18px;">IIMU Meeting Rooms</h2></div>'
          || '<div style="border:1px solid #e5e7eb;border-top:none;padding:20px;border-radius:0 0 8px 8px;background:#fff;">'
          || '<h3 style="margin:0 0 12px;color:#111827;font-size:16px;">' || v_title_safe || '</h3>'
          || '<p style="margin:0;color:#374151;font-size:14px;white-space:pre-line;line-height:1.5;">' || v_body_safe || '</p>'
          || '<p style="margin-top:24px;font-size:12px;color:#6b7280;">Open the scheduler: '
          || '<a href="https://meeting-rooms-iim-udaipur.lovable.app/my-bookings" style="color:#2563EB;">View in app</a></p>'
          || '</div></div>';

  BEGIN
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

    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, booking_id, notification_id)
    VALUES (NEW.user_id, v_email, NEW.title, 'sent', NEW.booking_id, NEW.id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, error, booking_id, notification_id)
    VALUES (NEW.user_id, v_email, NEW.title, 'failed', SQLERRM, NEW.booking_id, NEW.id);
  END;

  RETURN NEW;
END;
$function$;

-- Notify all admins when a booking enters pending_admin
CREATE OR REPLACE FUNCTION public.notify_admins_pending_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_room TEXT;
  v_owner TEXT;
  v_admin RECORD;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- Only fire on transition INTO pending_admin
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status <> 'pending_admin' THEN RETURN NEW; END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
  SELECT COALESCE(full_name, email) INTO v_owner
  FROM public.profiles WHERE user_id = NEW.user_id;

  v_title := 'Booking awaiting approval';
  v_body  := COALESCE(v_owner, 'A user') || '''s booking "' || NEW.title || '" in ' ||
             COALESCE(v_room, 'a room') || ' on ' || NEW.date || ' at ' ||
             to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') ||
             ' is ready for your approval.';

  FOR v_admin IN
    SELECT ur.user_id FROM public.user_roles ur WHERE ur.role = 'admin'
  LOOP
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_admin.user_id, 'booking_pending_admin', v_title, v_body, NEW.id);
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_admins_pending_approval_trigger ON public.bookings;
CREATE TRIGGER notify_admins_pending_approval_trigger
AFTER UPDATE ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.notify_admins_pending_approval();

-- Also fire on INSERT for solo bookings created directly as pending_admin
CREATE OR REPLACE FUNCTION public.notify_admins_pending_approval_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_room TEXT;
  v_owner TEXT;
  v_admin RECORD;
  v_title TEXT;
  v_body TEXT;
BEGIN
  IF NEW.status <> 'pending_admin' THEN RETURN NEW; END IF;

  SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
  SELECT COALESCE(full_name, email) INTO v_owner
  FROM public.profiles WHERE user_id = NEW.user_id;

  v_title := 'Booking awaiting approval';
  v_body  := COALESCE(v_owner, 'A user') || '''s booking "' || NEW.title || '" in ' ||
             COALESCE(v_room, 'a room') || ' on ' || NEW.date || ' at ' ||
             to_char(NEW.start_time, 'HH24:MI') || '–' || to_char(NEW.end_time, 'HH24:MI') ||
             ' is ready for your approval.';

  FOR v_admin IN
    SELECT ur.user_id FROM public.user_roles ur WHERE ur.role = 'admin'
  LOOP
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_admin.user_id, 'booking_pending_admin', v_title, v_body, NEW.id);
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_admins_pending_approval_insert_trigger ON public.bookings;
CREATE TRIGGER notify_admins_pending_approval_insert_trigger
AFTER INSERT ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION public.notify_admins_pending_approval_insert();
