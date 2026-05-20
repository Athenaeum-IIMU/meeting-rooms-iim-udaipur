import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors'
import { SMTPClient } from 'npm:emailjs@4.0.3'
import { createClient } from 'npm:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // --- Auth: require the internal shared secret set by the DB trigger ---
    const providedSecret = req.headers.get('x-send-email-secret') || ''
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(supabaseUrl, serviceRoleKey)

    const { data: expectedSecret, error: secretErr } = await admin.rpc('get_send_email_secret')
    if (secretErr || !expectedSecret || typeof expectedSecret !== 'string') {
      return new Response(JSON.stringify({ error: 'Server misconfigured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    // constant-time-ish comparison
    const a = new TextEncoder().encode(providedSecret)
    const b = new TextEncoder().encode(expectedSecret)
    let ok = a.length === b.length
    for (let i = 0; i < Math.min(a.length, b.length); i++) ok = ok && a[i] === b[i]
    if (!ok) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json().catch(() => null)
    const to = typeof body?.to === 'string' ? body.to.trim() : ''
    const subject = typeof body?.subject === 'string' ? body.subject.slice(0, 300) : ''
    const text = typeof body?.text === 'string' ? body.text.slice(0, 20000) : ''
    const html = typeof body?.html === 'string' ? body.html.slice(0, 50000) : ''

    const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRe.test(to) || to.length > 254 || !subject || (!text && !html)) {
      return new Response(JSON.stringify({ error: 'Invalid input' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Restrict recipient to a known profile email
    const { data: profile } = await admin
      .from('profiles')
      .select('email')
      .ilike('email', to)
      .maybeSingle()
    if (!profile) {
      return new Response(JSON.stringify({ error: 'Recipient not allowed' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const host = Deno.env.get('SMTP_HOST')!
    const port = parseInt(Deno.env.get('SMTP_PORT') || '465', 10)
    const user = Deno.env.get('SMTP_USERNAME')!
    const password = Deno.env.get('SMTP_PASSWORD')!
    const fromEmail = Deno.env.get('SMTP_FROM_EMAIL') || user

    const client = new SMTPClient({
      user,
      password,
      host,
      port,
      ssl: port === 465,
      tls: port !== 465,
    })

    const message: Record<string, unknown> = {
      from: `IIMU Meeting Rooms <${fromEmail}>`,
      to,
      subject,
      text: text || (html ? html.replace(/<[^>]+>/g, ' ') : ''),
    }
    if (html) {
      message.attachment = [{ data: html, alternative: true }]
    }

    await client.sendAsync(message as any)

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('send-email error:', error)
    return new Response(JSON.stringify({ success: false, error: 'Email send failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})