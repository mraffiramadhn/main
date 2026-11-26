# Treasury Notification Admin Panel

Route: `/treasury/notifications.html`

## Admin access
- Supabase Auth sign-in.
- Requires Treasury role `admin` or `superadmin`, membership in `treasury_editors`, and a valid single-device Treasury session (12-hour guard).
- Contact editing and manual invoice queueing are performed by protected RPCs; email contact records remain separate from public Treasury state.
- Contact updates and invoice queue actions write Treasury audit-log entries.

## Contact management
- Manage email, active status, consent, and manually confirmed email verification.
- Verification is manual in this initial stage: an admin should mark verified only after the student confirms the address. There is no OTP email flow yet.
- Changing email resets verified status, requiring verification again.
- Consent must be recorded; active + consent + verified are required for invoice queueing.

## Invoice controls
- Admin can queue a manual invoice/resend for a selected student.
- Server calculates current-period amount, arrears, and total from Treasury state; client cannot override invoice amounts.
- Queue is idempotent for scheduled invoices; manual queue requests use unique dedupe IDs to support resend records.
- **Queueing does not send email yet.** Delivery remains disabled until an email provider is configured and a secure delivery worker/Edge Function is deployed.
