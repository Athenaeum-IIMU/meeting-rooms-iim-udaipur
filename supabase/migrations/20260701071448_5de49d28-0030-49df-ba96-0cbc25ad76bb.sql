
-- 1) Block-slot enforcement on bookings
CREATE OR REPLACE FUNCTION public.enforce_no_blocked_slot_conflict()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_room TEXT; v_reason TEXT;
BEGIN
  IF public.has_role(auth.uid(), 'admin') THEN RETURN NEW; END IF;
  IF NEW.status IN ('cancelled','rejected') THEN RETURN NEW; END IF;
  SELECT bs.reason INTO v_reason FROM public.blocked_slots bs
   WHERE bs.room_id = NEW.room_id AND bs.date = NEW.date
     AND bs.start_time < NEW.end_time AND bs.end_time > NEW.start_time LIMIT 1;
  IF FOUND THEN
    SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
    RAISE EXCEPTION 'This time is blocked in % (%). Pick another slot.',
      COALESCE(v_room,'room'), COALESCE(v_reason,'admin block');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_no_blocked_slot ON public.bookings;
CREATE TRIGGER trg_enforce_no_blocked_slot
  BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_no_blocked_slot_conflict();


-- 2) Cross-user room-conflict enforcement on bookings
CREATE OR REPLACE FUNCTION public.enforce_room_conflict()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_conflict RECORD; v_room TEXT;
BEGIN
  IF NEW.status IN ('cancelled','rejected') THEN RETURN NEW; END IF;
  SELECT b.id, b.status INTO v_conflict FROM public.bookings b
   WHERE b.room_id = NEW.room_id AND b.date = NEW.date AND b.id <> NEW.id
     AND b.status IN ('approved','pending_admin','pending_members','needs_replacement')
     AND b.start_time < NEW.end_time AND b.end_time > NEW.start_time LIMIT 1;
  IF FOUND THEN
    SELECT name INTO v_room FROM public.rooms WHERE id = NEW.room_id;
    RAISE EXCEPTION 'This slot in % (%-%) overlaps another booking (%). Pick a different time or room.',
      COALESCE(v_room,'room'),
      to_char(NEW.start_time,'HH24:MI'), to_char(NEW.end_time,'HH24:MI'),
      v_conflict.status;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_room_conflict ON public.bookings;
CREATE TRIGGER trg_enforce_room_conflict
  BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_room_conflict();


-- 3) Auto-reject overlapping pending bookings when one is approved
CREATE OR REPLACE FUNCTION public.auto_reject_overlapping_on_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
    UPDATE public.bookings
       SET status = 'rejected',
           rejection_reason = COALESCE(rejection_reason,'Another booking for this room and time was approved.')
     WHERE id <> NEW.id AND room_id = NEW.room_id AND date = NEW.date
       AND start_time < NEW.end_time AND end_time > NEW.start_time
       AND status IN ('pending_admin','pending_members','needs_replacement');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_auto_reject_overlapping ON public.bookings;
CREATE TRIGGER trg_auto_reject_overlapping
  AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.auto_reject_overlapping_on_approval();


-- 4) Fix cleanup_old_data email + notify_user_by_email to use net.http_post
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE
  v_cutoff DATE := CURRENT_DATE - INTERVAL '1 day';
  v_bookings_html TEXT := ''; v_blocked_html TEXT := '';
  v_bookings_text TEXT := ''; v_blocked_text TEXT := '';
  v_count_b INT := 0; v_count_s INT := 0;
  v_row RECORD;
  v_url TEXT := 'https://olvjcbfdzqwkanaavftq.supabase.co/functions/v1/send-email';
  v_secret TEXT; v_html TEXT;
BEGIN
  FOR v_row IN
    SELECT b.id, b.title, b.date, b.start_time, b.end_time, b.status,
           COALESCE(r.name,'Unknown') AS room_name,
           COALESCE(p.full_name, p.email,'Unknown') AS organizer,
           p.email AS organizer_email,
           COALESCE((SELECT string_agg(bm.email, ', ' ORDER BY bm.email)
                     FROM public.booking_members bm WHERE bm.booking_id = b.id),'') AS members
      FROM public.bookings b
      LEFT JOIN public.rooms r ON r.id = b.room_id
      LEFT JOIN public.profiles p ON p.user_id = b.user_id
     WHERE b.date < v_cutoff ORDER BY b.date, b.start_time
  LOOP
    v_count_b := v_count_b + 1;
    v_bookings_html := v_bookings_html ||
      '<tr><td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.date ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| to_char(v_row.start_time,'HH24:MI')||'-'||to_char(v_row.end_time,'HH24:MI') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.room_name ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(v_row.title,'<','&lt;') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.organizer ||' ('|| COALESCE(v_row.organizer_email,'') ||')</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.status ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.members ||'</td></tr>';
    v_bookings_text := v_bookings_text || v_row.date ||' '|| to_char(v_row.start_time,'HH24:MI')||'-'||to_char(v_row.end_time,'HH24:MI')
      ||' | '|| v_row.room_name ||' | '|| v_row.title ||' | '|| v_row.organizer
      ||' | status='|| v_row.status ||' | members='|| v_row.members || E'\n';
  END LOOP;

  FOR v_row IN
    SELECT bs.id, bs.date, bs.start_time, bs.end_time, bs.reason,
           COALESCE(r.name,'Unknown') AS room_name,
           COALESCE(p.full_name, p.email,'Unknown') AS creator
      FROM public.blocked_slots bs
      LEFT JOIN public.rooms r ON r.id = bs.room_id
      LEFT JOIN public.profiles p ON p.user_id = bs.created_by
     WHERE bs.date < v_cutoff ORDER BY bs.date, bs.start_time
  LOOP
    v_count_s := v_count_s + 1;
    v_blocked_html := v_blocked_html ||
      '<tr><td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.date ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| to_char(v_row.start_time,'HH24:MI')||'-'||to_char(v_row.end_time,'HH24:MI') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.room_name ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| COALESCE(replace(v_row.reason,'<','&lt;'),'') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.creator ||'</td></tr>';
    v_blocked_text := v_blocked_text || v_row.date ||' '|| to_char(v_row.start_time,'HH24:MI')||'-'||to_char(v_row.end_time,'HH24:MI')
      ||' | '|| v_row.room_name ||' | reason='|| COALESCE(v_row.reason,'') ||' | by '|| v_row.creator || E'\n';
  END LOOP;

  IF v_count_b > 0 OR v_count_s > 0 THEN
    SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name='send_email_secret' LIMIT 1;
    v_html := '<div style="font-family:Arial,sans-serif;max-width:900px;margin:0 auto;padding:24px;">'
           || '<div style="background:#2563EB;color:#fff;padding:16px 20px;border-radius:8px 8px 0 0;">'
           || '<h2 style="margin:0;font-size:18px;">IIMU Meeting Rooms - Daily Cleanup Archive</h2>'
           || '<p style="margin:6px 0 0;font-size:13px;opacity:.9;">Records dated before '|| v_cutoff ||' (about to be deleted)</p></div>'
           || '<div style="border:1px solid #e5e7eb;border-top:none;padding:20px;border-radius:0 0 8px 8px;background:#fff;font-size:13px;color:#111827;">'
           || '<h3 style="margin:0 0 8px;">Bookings ('|| v_count_b ||')</h3>';
    IF v_count_b > 0 THEN
      v_html := v_html || '<table style="border-collapse:collapse;width:100%;font-size:12px;"><thead><tr style="background:#f3f4f6;">'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Date</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Time</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Room</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Title</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Organizer</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Status</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Members</th>'
        ||'</tr></thead><tbody>'|| v_bookings_html ||'</tbody></table>';
    ELSE v_html := v_html || '<p style="color:#6b7280;">No bookings.</p>';
    END IF;
    v_html := v_html || '<h3 style="margin:20px 0 8px;">Blocked Slots ('|| v_count_s ||')</h3>';
    IF v_count_s > 0 THEN
      v_html := v_html || '<table style="border-collapse:collapse;width:100%;font-size:12px;"><thead><tr style="background:#f3f4f6;">'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Date</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Time</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Room</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Reason</th>'
        ||'<th style="padding:6px 8px;border:1px solid #e5e7eb;text-align:left;">Created by</th>'
        ||'</tr></thead><tbody>'|| v_blocked_html ||'</tbody></table>';
    ELSE v_html := v_html || '<p style="color:#6b7280;">No blocked slots.</p>';
    END IF;
    v_html := v_html || '</div></div>';

    BEGIN
      PERFORM net.http_post(
        url := v_url,
        headers := jsonb_build_object('Content-Type','application/json','x-send-email-secret', COALESCE(v_secret,'')),
        body := jsonb_build_object(
          'to','readers.library@iimu.ac.in',
          'subject','IIMU Meeting Rooms - Daily Cleanup Archive ('|| v_cutoff ||')',
          'html', v_html,
          'text','Daily cleanup archive for records dated before '|| v_cutoff || E'\n\n'
                ||'Bookings ('|| v_count_b ||'):'|| E'\n' || v_bookings_text || E'\n'
                ||'Blocked Slots ('|| v_count_s ||'):'|| E'\n' || v_blocked_text
        ),
        timeout_milliseconds := 30000
      );
      INSERT INTO public.email_delivery_log (user_id, recipient, subject, status)
      VALUES (NULL,'readers.library@iimu.ac.in','Daily Cleanup Archive ('|| v_cutoff ||')','sent');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, error)
      VALUES (NULL,'readers.library@iimu.ac.in','Daily Cleanup Archive ('|| v_cutoff ||')','failed', SQLERRM);
    END;
  END IF;

  DELETE FROM public.notifications WHERE created_at < now() - INTERVAL '1 day';
  DELETE FROM public.email_delivery_log WHERE created_at < now() - INTERVAL '1 day';
  DELETE FROM public.audit_log WHERE created_at < now() - INTERVAL '30 days';
  DELETE FROM public.booking_members
    WHERE booking_id IN (SELECT id FROM public.bookings WHERE date < v_cutoff);
  DELETE FROM public.notifications
    WHERE booking_id IN (SELECT id FROM public.bookings WHERE date < v_cutoff);
  DELETE FROM public.email_delivery_log
    WHERE booking_id IN (SELECT id FROM public.bookings WHERE date < v_cutoff);
  DELETE FROM public.waitlist WHERE date < v_cutoff;
  DELETE FROM public.bookings WHERE date < v_cutoff;
  DELETE FROM public.blocked_slots WHERE date < v_cutoff;
END;
$function$;


CREATE OR REPLACE FUNCTION public.notify_user_by_email(p_email text, p_type text, p_title text, p_body text, p_booking_id uuid DEFAULT NULL::uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public','net','extensions'
AS $function$
DECLARE
  v_user_id UUID; v_url TEXT := 'https://olvjcbfdzqwkanaavftq.supabase.co/functions/v1/send-email';
  v_secret TEXT; v_html TEXT; v_title_safe TEXT; v_body_safe TEXT;
BEGIN
  SELECT user_id INTO v_user_id FROM public.profiles WHERE LOWER(email)=LOWER(p_email) LIMIT 1;
  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, body, booking_id)
    VALUES (v_user_id, p_type, p_title, p_body, p_booking_id);
    RETURN;
  END IF;

  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name='send_email_secret' LIMIT 1;
  v_title_safe := replace(replace(replace(replace(replace(COALESCE(p_title,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;');
  v_body_safe  := replace(replace(replace(replace(replace(COALESCE(p_body,''), '&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;');
  v_html := '<div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">'
         || '<div style="background:#2563EB;color:#fff;padding:16px 20px;border-radius:8px 8px 0 0;">'
         || '<h2 style="margin:0;font-size:18px;">IIMU Meeting Rooms</h2></div>'
         || '<div style="border:1px solid #e5e7eb;border-top:none;padding:20px;border-radius:0 0 8px 8px;background:#fff;">'
         || '<h3 style="margin:0 0 12px;color:#111827;font-size:16px;">'|| v_title_safe ||'</h3>'
         || '<p style="margin:0;color:#374151;font-size:14px;white-space:pre-line;line-height:1.5;">'|| v_body_safe ||'</p>'
         || '<p style="margin-top:24px;font-size:12px;color:#6b7280;">Sign in to respond: '
         || '<a href="https://meeting-rooms-iim-udaipur.lovable.app/my-bookings" style="color:#2563EB;">Open the scheduler</a></p>'
         || '</div></div>';
  BEGIN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type','application/json','x-send-email-secret', COALESCE(v_secret,'')),
      body := jsonb_build_object('to', p_email,'subject', p_title,'html', v_html,'text', p_title || E'\n\n' || p_body),
      timeout_milliseconds := 30000
    );
    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, booking_id)
    VALUES (NULL, p_email, p_title, 'sent', p_booking_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, error, booking_id)
    VALUES (NULL, p_email, p_title, 'failed', SQLERRM, p_booking_id);
  END;
END;
$function$;


-- 5) Clean current FUTURE violations only (past bookings blocked by past-time trigger)
UPDATE public.bookings b
SET status='cancelled',
    rejection_reason=COALESCE(rejection_reason,'Overlaps an admin-blocked slot (auto-cleaned).')
WHERE b.status IN ('approved','pending_admin','pending_members','needs_replacement')
  AND b.date >= CURRENT_DATE
  AND EXISTS (SELECT 1 FROM public.blocked_slots bs
              WHERE bs.room_id=b.room_id AND bs.date=b.date
                AND bs.start_time < b.end_time AND bs.end_time > b.start_time);

WITH ranked AS (
  SELECT id, room_id, date, start_time, end_time, created_at,
         row_number() OVER (PARTITION BY room_id, date ORDER BY created_at) rn
    FROM public.bookings
   WHERE status IN ('approved','pending_admin','pending_members','needs_replacement')
     AND date >= CURRENT_DATE
),
losers AS (
  SELECT DISTINCT r2.id FROM ranked r1 JOIN ranked r2
    ON r1.room_id=r2.room_id AND r1.date=r2.date AND r1.id<>r2.id
   AND r1.start_time < r2.end_time AND r1.end_time > r2.start_time
   AND r1.rn < r2.rn
)
UPDATE public.bookings SET status='rejected',
    rejection_reason=COALESCE(rejection_reason,'Overlaps an earlier booking (auto-cleaned).')
WHERE id IN (SELECT id FROM losers);
