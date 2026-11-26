# 06 — Notifications and Scheduling

## 1. Delivery architecture
- Flutter registers FCM token after authenticated login and notification permission.
- Store token in `device_tokens`, linked to profile.
- Supabase Cron runs scheduled Edge Functions.
- Edge Function creates a durable `notification_events` row before delivery.
- Unique `dedupe_key` prevents duplicate logical notifications.
- FCM sends to active device tokens.
- Update event status and delivery metadata.
- Failed deliveries can be retried with bounded exponential backoff.

## 2. Timezone
Property timezone defaults to `Asia/Dhaka`. Cron must interpret day 1 using this timezone. Use `date` values for billing dates and avoid converting local due dates through UTC midnight in a way that shifts the calendar date.

## 3. Rent reminder schedule
Run at 09:00 Asia/Dhaka on the first day of each month.
Select rent obligations:
- due_date is within current local calendar month
- outstanding > 0
- agreement is active (or obligation remains collectible under ended agreement policy)
- recipient has opted into reminders
Create dedupe key such as:
`rent_due:{profile_id}:{obligation_id}:{YYYY-MM}`

The reminder is sent once per recipient and obligation in that due month. Do not send another daily rent reminder unless a separate preference is deliberately introduced.

## 4. Agreement expiry schedule
Run at 09:15 Asia/Dhaka on day 1.
Select active agreements where expiry date is within the next three calendar months (inclusive policy to be confirmed).
Dedupe key:
`agreement_expiry:{profile_id}:{agreement_id}:{YYYY-MM}`

Send to owner and linked tenant if tenant notifications are enabled. If tenant has no portal account, notify owner only.

## 5. In-app notification inbox
Notification categories:
- Rent due
- Rent overdue (optional later)
- Agreement expiry
- Payment receipt
- Deposit adjustment
- Owner announcement (future)

Each notification stores title, body, event type, reference, read timestamp, and created timestamp. Consider a separate `notification_reads` table only if one event can be shared across recipients; simplest MVP is one event row per recipient with `read_at`.

## 6. Android setup
- Configure Firebase Android app and `google-services.json` for each flavor/package ID.
- Request Android 13+ notification permission at a user-understandable moment.
- Create channels: `rent_reminders`, `agreement_alerts`, `payments`.
- Handle foreground, background and terminated notification taps.
- Deep-link to relevant screen, e.g. `/tenant/rent/obligation-id`.
- Do not put sensitive personal data or full account details in push payloads. Fetch details after opening app.

## 7. Operational safeguards
- Log job start/end, candidate count, created event count, sent count and failure count.
- Alert owner/admin if scheduled job fails repeatedly.
- Provide a manual “send test notification” function for development only.
- Test duplicate Cron invocation and FCM failure scenarios.


## 8. Confirmed recipient policy
Agreement expiry reminders are for both owner and tenant. Create recipient-specific notification events and dedupe keys. A tenant without a linked authenticated profile receives no push notification; the owner still receives the alert. Do not expose another tenant's agreement details in any notification.


## 9. Bilingual notification templates
- Store notification template keys and localized content for `bn_BD` and `en`.
- Resolve locale per recipient profile. Owner and tenant can receive the same event in different languages.
- Use localized month names, dates and BDT display formatting while retaining canonical IDs and amounts in payload data.
- Push payloads should include stable `event_type`, entity IDs and deep-link route data; do not rely on translated title/body for app behavior.
- Test Bangla glyph display in Android notification tray on supported Android versions and device manufacturers.


## 9. Implemented database generators (migration 0010)
- `generate_monthly_rent_reminders(p_run_date)` selects obligations whose actual `due_date` falls in `date_trunc('month', p_run_date)` and whose `outstanding_minor > 0` (so an arrears November obligation due 5 December is reminded on 1 December, never 1 November). Deduplication key: `rent_due:YYYY-MM:{obligation_id}:{recipient_profile_id}`.
- `generate_agreement_expiry_reminders(p_run_date)` selects active/expiring agreements with `expiry_date` inside the 3-calendar-month window `[month_start, month_start + 3 months - 1 day]`. Deduplication key: `agr_expiry:YYYY-MM:{agreement_id}:{recipient_profile_id}`. Both functions are restricted to `service_role`.
