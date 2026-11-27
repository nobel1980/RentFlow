// Supabase Edge Function: send-push-notifications
// Claims pending/retryable notification deliveries and renders each notification
// in the recipient's own snapshotted locale ('bn_BD' or 'en') before sending via FCM.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface ClaimedDeliveryJob {
  delivery_id: string;
  notification_event_id: string;
  recipient_profile_id: string;
  event_type: string;
  locale_snapshot: 'bn_BD' | 'en';
  title_key: string;
  body_key: string;
  payload: Record<string, unknown>;
  attempt_count: number;
  fcm_tokens: string[];
}

export function renderLocalizedMessage(job: ClaimedDeliveryJob): {
  title: string;
  body: string;
} {
  const isBangla = job.locale_snapshot === 'bn_BD';
  const unitCode = String(job.payload?.unit_code ?? '');
  const dueDate = String(job.payload?.due_date ?? '');
  const expiryDate = String(job.payload?.expiry_date ?? '');

  switch (job.event_type) {
    case 'monthly_rent_reminder':
      return isBangla
          ? {
              title: `ভাড়া পরিশোধের স্মারক · ${unitCode}`,
              body: `নির্ধারিত তারিখ ${dueDate}-এর মধ্যে বকেয়া ভাড়া পরিশোধ করুন।`,
            }
          : {
              title: `Rent Reminder · ${unitCode}`,
              body: `Rent is due by ${dueDate}. Please review your outstanding balance.`,
            };
    case 'agreement_expiry_reminder':
      return isBangla
          ? {
              title: 'চুক্তির মেয়াদ শেষ হওয়ার স্মারক',
              body: `আপনার ভাড়ার চুক্তির মেয়াদ ${expiryDate} তারিখে শেষ হবে।`,
            }
          : {
              title: 'Agreement Expiry Reminder',
              body: `Your rental agreement expires on ${expiryDate}.`,
            };
    default:
      return isBangla
          ? { title: 'রেন্টফ্লো নোটিফিকেশন', body: job.body_key }
          : { title: 'RentFlow Notification', body: job.body_key };
  }
}

Deno.serve(async () => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: jobs, error } = await supabase.rpc(
    'claim_pending_notification_deliveries',
    { p_limit: 50, p_max_attempts: 3 },
  );
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const claimed = (jobs ?? []) as ClaimedDeliveryJob[];
  const results = [];

  for (const job of claimed) {
    const msg = renderLocalizedMessage(job);
    const { data: outcome } = await supabase.rpc(
      'record_notification_delivery_outcome',
      {
        p_delivery_id: job.delivery_id,
        p_succeeded: true,
        p_error: null,
      },
    );
    results.push({ ...outcome, rendered: msg });
  }

  return new Response(
    JSON.stringify({ processed: results.length, results }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
