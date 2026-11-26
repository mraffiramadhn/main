# Treasury Weekly Invoice Automation (v1)

## Schedule
- Runs Monday 00:00 WIB (Asia/Jakarta), using Supabase Cron at Sunday 17:00 UTC.
- Generates invoices for the current billing week plus arrears from earlier billed weeks.
- Uses the canonical Treasury calendar. October-4 is intentionally excluded.
- Deadline is Friday of the current period (start date + 4 days).
- Fully paid students are not queued.

## Queue-only stage
This automation currently **does not send email**. It creates private pending notification rows only for contacts whose email is both verified and consented. No contacts are configured yet, so test runs skip all recipients.

## Data privacy
- Student email addresses live in `treasury_notification_contacts`, separate from the public `treasury_state` JSON payload.
- RLS restricts contacts, queue, and run logs to authenticated Treasury admin/superadmin users with a valid Treasury session.
- No email data should be added to public roster/state JSON.
- Sending must remain disabled until a consented, verified email contact flow and provider secret are configured.

## Tables
- `treasury_notification_contacts`: private email contact map, consent/verification flags.
- `treasury_notification_queue`: idempotent queued invoice records with dedupe keys.
- `treasury_notification_runs`: scheduler/test run results.

## Test
Run:
`select public.treasury_enqueue_weekly_invoice_notifications();`

Expected before contacts are configured: `queued=0`; `skipped_no_contact` equals students with outstanding amounts.
