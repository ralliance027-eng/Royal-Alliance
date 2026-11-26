# Royal Alliance Annual Member Draw System

## Requirements
- Node.js 20.9 or newer
- npm 10 or newer
- Supabase project with the migrations applied

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. Install the exact versions listed in `package.json` with `npm install`.
4. Run `npm run dev` for development or `npm run build` for a production build.
5. Run `npm run check:release` for static release checks.

## Supabase Edge Function configuration
Configure secrets only in Supabase Edge Function secrets; never put service-role keys or provider secrets in `.env.local` or any `NEXT_PUBLIC_*` variable.

Required for browser invocation of `create-user` and `send-whatsapp`:
- `APP_ALLOWED_ORIGINS`: comma-separated exact origins, for example `http://localhost:3000,https://your-real-domain.example`. Replace the example with the real deployed app origin(s). Do not use `*`.

The Supabase runtime provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions.

Optional WhatsApp Cloud API configuration:
- `WHATSAPP_ACCESS_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_API_VERSION` (default `v21.0`)
- `WHATSAPP_TEMPLATE_LANGUAGE` (default `en`)
- `WHATSAPP_DEFAULT_COUNTRY_CODE` (default `91`)
- `WHATSAPP_PAYMENT_TEMPLATE` (default `payment_confirmation`)
- `WHATSAPP_WINNER_TEMPLATE` (default `draw_winner_announcement`)

For the `whatsapp-webhook` function, configure:
- `WHATSAPP_WEBHOOK_VERIFY_TOKEN`
- `WHATSAPP_APP_SECRET`

Then configure the Meta webhook callback URL as `https://YOUR_PROJECT_REF.supabase.co/functions/v1/whatsapp-webhook`, subscribe to message status events, and use the same verify token in Meta and Supabase.

## Important migration note
The connected live Supabase project has a migration ledger that is not one-to-one with the uploaded ZIP's original SQL filenames. Several live migration versions/names have no matching SQL file in the supplied archive, while the archive contains older baseline SQL files whose versions are not in the live ledger. The supplied local filenames are normalized to 14-digit timestamps, but this does **not** make the historical SQL content identical to the remote migration ledger. Do not run `supabase db reset` or blindly `supabase db push` against the live project. Reconcile the missing historical SQL from the authoritative source repository before using a fresh-project migration workflow.

## Security notes
- Browser Supabase client uses only the publishable key.
- Service-role access is restricted to Edge Functions/server-side code.
- Code migration history is RLS-protected and append-only for application clients; database triggers record member/agent code changes.
- Admin-only operational RPCs remain `SECURITY DEFINER` by design and perform role/scope checks internally. Review these checks when changing business rules.
