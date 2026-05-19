import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors'
import { SMTPClient } from 'npm:emailjs@4.0.3'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { to, subject, text, html } = await req.json()
    if (!to || !subject || (!text && !html)) {
      return new Response(JSON.stringify({ error: 'Missing to/subject/body' }), {
        status: 400,
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
    const msg = error instanceof Error ? error.message : String(error)
    return new Response(JSON.stringify({ success: false, error: msg }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})