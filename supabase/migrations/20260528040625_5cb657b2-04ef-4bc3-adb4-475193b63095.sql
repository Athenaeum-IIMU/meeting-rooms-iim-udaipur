
-- 1) Backfill user_id on existing booking_members from profiles by email match
UPDATE public.booking_members bm
SET user_id = p.user_id
FROM public.profiles p
WHERE bm.user_id IS NULL
  AND LOWER(bm.email) = LOWER(p.email);

-- 2) When a profile is created (user signs up), backfill any pending invites
--    that were sent to this email before signup.
CREATE OR REPLACE FUNCTION public.backfill_booking_members_on_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.booking_members bm
  SET user_id = NEW.user_id
  WHERE bm.user_id IS NULL
    AND LOWER(bm.email) = LOWER(NEW.email);
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.backfill_booking_members_on_profile() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_backfill_booking_members_on_profile ON public.profiles;
CREATE TRIGGER trg_backfill_booking_members_on_profile
AFTER INSERT OR UPDATE OF email ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.backfill_booking_members_on_profile();

-- 3) Send email directly to invitees even when they don't yet have a profile/account.
--    notify_user_by_email previously short-circuited when no profile existed,
--    so unregistered invitees received nothing.
CREATE OR REPLACE FUNCTION public.notify_user_by_email(
  p_email text, p_type text, p_title text, p_body text, p_booking_id uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_url     TEXT := 'https://olvjcbfdzqwkanaavftq.supabase.co/functions/v1/send-email';
  v_secret  TEXT;
  v_html    TEXT;
  v_title_safe TEXT;
  v_body_safe  TEXT;
BEGIN
  SELECT user_id INTO v_user_id
  FROM public.profiles
  WHERE LOWER(email) = LOWER(p_email)
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    -- In-app notification (its AFTER INSERT trigger will email the user too).
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_user_id, p_type, p_title, p_body, p_booking_id);
    RETURN;
  END IF;

  -- No profile yet — send a direct email so they know about the invite/update.
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'send_email_secret' LIMIT 1;

  v_title_safe := replace(replace(replace(replace(replace(COALESCE(p_title,''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
  v_body_safe := replace(replace(replace(replace(replace(COALESCE(p_body,''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');

  v_html := '<div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">'
         || '<div style="background:#2563EB;color:#fff;padding:16px 20px;border-radius:8px 8px 0 0;">'
         || '<h2 style="margin:0;font-size:18px;">IIMU Meeting Rooms</h2></div>'
         || '<div style="border:1px solid #e5e7eb;border-top:none;padding:20px;border-radius:0 0 8px 8px;background:#fff;">'
         || '<h3 style="margin:0 0 12px;color:#111827;font-size:16px;">' || v_title_safe || '</h3>'
         || '<p style="margin:0;color:#374151;font-size:14px;white-space:pre-line;line-height:1.5;">' || v_body_safe || '</p>'
         || '<p style="margin-top:24px;font-size:12px;color:#6b7280;">Sign in to respond: '
         || '<a href="https://meeting-rooms-iim-udaipur.lovable.app/my-bookings" style="color:#2563EB;">Open the scheduler</a></p>'
         || '</div></div>';

  BEGIN
    PERFORM extensions.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-send-email-secret', COALESCE(v_secret, '')
      ),
      body := jsonb_build_object(
        'to', p_email,
        'subject', p_title,
        'html', v_html,
        'text', p_title || E'\n\n' || p_body
      ),
      timeout_milliseconds := 30000
    );
    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, booking_id)
    VALUES (NULL, p_email, p_title, 'sent', p_booking_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, error, booking_id)
    VALUES (NULL, p_email, p_title, 'failed', SQLERRM, p_booking_id);
  END;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.notify_user_by_email(text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
