# Royal Alliance V25 — WhatsApp Manual + Automatic

## Included
- WhatsApp dashboard section has automatic payment-confirmation and draw-winner notification hooks.
- Admin/Super Admin can manually choose a saved Member or active Agent, review the stored mobile number, compose a text message (up to 4096 characters), confirm consent, and send.
- Recipient phone number is looked up server-side from the selected record; the browser does not submit an arbitrary phone destination.
- Function verifies authenticated user and active Admin/Super Admin role. Admin sends are limited to their assigned team.
- Notification log records recipient type/record, message text, consent confirmation, status, provider ID and errors.
- Existing records are preserved; no delete/reset is part of this change.

## Live changes performed
- Added columns and index to `public.notification_logs` using an additive migration on the connected Royal Alliance project.

## Not certified yet
- Deployment of `send-whatsapp` was not confirmed; the deploy operation was blocked, and the live project previously did not list this function.
- WhatsApp delivery requires Meta WhatsApp Cloud API secrets (`WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`), approved templates for automatic messages, correct template language and user consent. Free-form manual text may only be delivered during Meta's customer-service window; outside it, an approved template flow is required.
- Production build, browser E2E, RLS negative tests, and end-to-end provider delivery are not certified.
- Review/reconcile remote migration history before treating the database as fully reproducible from source.

## Deployment
Deploy `supabase/functions/send-whatsapp` with JWT verification enabled and configure secrets in Supabase Edge Function settings. Do not put service-role or WhatsApp access tokens in `.env` variables prefixed with `NEXT_PUBLIC_`.
