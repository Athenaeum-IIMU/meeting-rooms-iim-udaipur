
-- ============================================================
-- 1. Performance indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_bookings_date_status ON public.bookings(date, status);
CREATE INDEX IF NOT EXISTS idx_bookings_room_date_status ON public.bookings(room_id, date, status);
CREATE INDEX IF NOT EXISTS idx_booking_members_booking_user ON public.booking_members(booking_id, user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON public.audit_log(created_at DESC);

-- ============================================================
-- 2. Reduce email volume: filter types + skip self-actions
-- ============================================================
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
    'reminder'
  ];
BEGIN
  -- Only email for high-signal notification types
  IF NOT (NEW.type = ANY (v_allowed_types)) THEN
    RETURN NEW;
  END IF;

  -- Don't email the actor for their own action
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

-- ============================================================
-- 3. Scheduled retention cleanup
-- ============================================================
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  -- Notifications older than 1 day
  DELETE FROM public.notifications WHERE created_at < now() - INTERVAL '1 day';

  -- Email delivery log older than 2 days
  DELETE FROM public.email_delivery_log WHERE created_at < now() - INTERVAL '2 days';

  -- Audit log older than 30 days
  DELETE FROM public.audit_log WHERE created_at < now() - INTERVAL '30 days';

  -- Past bookings older than 2 days (never touch today/future)
  DELETE FROM public.booking_members
  WHERE booking_id IN (
    SELECT id FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '2 days'
  );
  DELETE FROM public.notifications
  WHERE booking_id IN (
    SELECT id FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '2 days'
  );
  DELETE FROM public.email_delivery_log
  WHERE booking_id IN (
    SELECT id FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '2 days'
  );
  DELETE FROM public.waitlist WHERE date < CURRENT_DATE - INTERVAL '2 days';
  DELETE FROM public.bookings WHERE date < CURRENT_DATE - INTERVAL '2 days';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_old_data() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. Schedule daily via pg_cron (03:00 UTC = 08:30 IST)
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  PERFORM cron.unschedule('daily-cleanup-old-data');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'daily-cleanup-old-data',
  '0 3 * * *',
  $$SELECT public.cleanup_old_data();$$
);
