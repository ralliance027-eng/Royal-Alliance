# Royal Alliance V19 — database connection and schema update

## Connected Supabase project checked
- Project ref: `ppsvxrvsgfnplsrnkubv` (`ralliance Project`)
- Project status at inspection: `ACTIVE_HEALTHY`
- `create-user` Edge Function: deployed, ACTIVE, version 2, JWT verification enabled.
- Existing `public` tables and RLS policies were inspected through the connected Supabase account.
- Existing profile records included the configured Super Admin and one active Admin.
- The migration history API returned no recorded migrations even though the tables/functions exist. This suggests the live schema may have been applied manually or its migration history is not synced. Do NOT run all old migrations blindly on production.

## New additive schema
`supabase/migrations/202610090012_multi_prize_booking_products.sql` was applied to the connected project successfully. It adds:
- `draw_prizes`: multiple prize types and quantities per monthly draw.
- `draw_results`: multiple winner records per draw/prize.
- `booking_products`: separate catalogue for non-draw fallback products.
- `member_booking_choices`: member choice states `not_yet_chosen`, `chosen`, `allocated`, `delivered`.
- RLS policies for manager control and member/team scoped choices.

The old `draws.winner_member_id` column remains for compatibility. The current UI still needs further work to manage the new tables end-to-end; adding the database schema does not automatically add booking-product screens or multi-winner draw controls.

## Admin account creation
`create-user` was deployed to version 2 from the package function source. It uses direct `auth.admin.createUser({ email_confirm: true })` rather than an invitation function. The function checks caller session and role and rolls back the Auth user if profile update fails. Actual browser submission/login still needs an end-to-end test.

## Local deploy commands
```powershell
npx supabase link --project-ref ppsvxrvsgfnplsrnkubv
npx supabase functions deploy create-user
```
No Docker is normally required for a cloud-only Supabase function deployment. If CLI bundling hangs, the hosted Supabase function deployment path was used for `create-user`.

## Release gates still open
- `npm ci` clean install and `npm run build`
- Browser test: create Admin without invitation email, then sign in with entered password.
- RLS negative tests across Admin/Agent accounts.
- Implement and test UI for draw_prizes/draw_results and booking_products/member_booking_choices.
- Financial E2E and WhatsApp live send tests.
