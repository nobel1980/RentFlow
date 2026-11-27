// Supabase Edge Function: run-day1-scheduled-jobs
// Scheduled via Supabase Cron on day 1 of each month in Asia/Dhaka.
// Invokes the idempotent service_role PostgreSQL RPCs:
// 1. generate_all_rent_obligations
// 2. generate_monthly_rent_reminders (actual due_date in current month & outstanding > 0)
// 3. generate_agreement_expiry_reminders (3-calendar-month window)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'Missing server environment credentials' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
  const runDate: string | null = body?.run_date ?? null;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: obligationsCreated, error: obErr } = await supabase.rpc(
    'generate_all_rent_obligations',
    { p_through: runDate },
  );
  if (obErr) {
    return new Response(JSON.stringify({ error: obErr.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { data: rentReminders, error: rentErr } = await supabase.rpc(
    'generate_monthly_rent_reminders',
    { p_run_date: runDate },
  );
  if (rentErr) {
    return new Response(JSON.stringify({ error: rentErr.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { data: expiryReminders, error: expErr } = await supabase.rpc(
    'generate_agreement_expiry_reminders',
    { p_run_date: runDate },
  );
  if (expErr) {
    return new Response(JSON.stringify({ error: expErr.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(
    JSON.stringify({
      obligations_created: obligationsCreated,
      rent_reminders: rentReminders,
      expiry_reminders: expiryReminders,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
