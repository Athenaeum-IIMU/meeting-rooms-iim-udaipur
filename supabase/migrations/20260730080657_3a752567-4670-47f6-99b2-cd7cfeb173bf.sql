CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_cutoff DATE := CURRENT_DATE;
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
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.room_name,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.title,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.organizer,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||' ('|| replace(replace(replace(replace(replace(COALESCE(v_row.organizer_email,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||')</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| v_row.status ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.members,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||'</td></tr>';
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
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.room_name,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.reason,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||'</td>'||
      '<td style="padding:6px 8px;border:1px solid #e5e7eb;">'|| replace(replace(replace(replace(replace(COALESCE(v_row.creator,''),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;') ||'</td></tr>';
    v_blocked_text := v_blocked_text || v_row.date ||' '|| to_char(v_row.start_time,'HH24:MI')||'-'||to_char(v_row.end_time,'HH24:MI')
      ||' | '|| v_row.room_name ||' | reason='|| COALESCE(v_row.reason,'') ||' | by '|| v_row.creator || E'\n';
  END LOOP;

  IF v_count_b > 0 OR v_count_s > 0 THEN
    SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name='send_email_secret' LIMIT 1;
    v_html := '<div style="font-family:Arial,sans-serif;max-width:900px;margin:0 auto;padding:24px;">'
           || '<div style="background:#2563EB;color:#fff;padding:16px 20px;border-radius:8px 8px 0 0;">'
           || '<h2 style="margin:0;font-size:18px;">IIMU Meeting Rooms - Daily Cleanup Archive</h2>'
           || '<p style="margin:6px 0 0;font-size:13px;opacity:.9;">All records up to and including '|| (v_cutoff - 1) ||' (about to be deleted; only '|| v_cutoff ||' onwards is kept)</p></div>'
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
          'subject','IIMU Meeting Rooms - Daily Cleanup Archive (up to '|| (v_cutoff - 1) ||')',
          'html', v_html,
          'text','Daily cleanup archive for all records up to and including '|| (v_cutoff - 1) || E'\n\n'
                ||'Bookings ('|| v_count_b ||'):'|| E'\n' || v_bookings_text || E'\n'
                ||'Blocked Slots ('|| v_count_s ||'):'|| E'\n' || v_blocked_text
        ),
        timeout_milliseconds := 30000
      );
      INSERT INTO public.email_delivery_log (user_id, recipient, subject, status)
      VALUES (NULL,'readers.library@iimu.ac.in','Daily Cleanup Archive (up to '|| (v_cutoff - 1) ||')','sent');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.email_delivery_log (user_id, recipient, subject, status, error)
      VALUES (NULL,'readers.library@iimu.ac.in','Daily Cleanup Archive (up to '|| (v_cutoff - 1) ||')','failed', SQLERRM);
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
$fn$;

REVOKE ALL ON FUNCTION public.cleanup_old_data() FROM PUBLIC, anon, authenticated;