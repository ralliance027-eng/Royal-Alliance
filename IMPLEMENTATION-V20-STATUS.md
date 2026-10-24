# Royal Alliance V20 — Multi-prize draws and booking products

## Implemented in source and migrations
- Connected Supabase project `ppsvxrvsgfnplsrnkubv` inspected; the existing `create-user` Edge Function was redeployed as version 2 with JWT verification enabled and npm: Supabase JS import.
- Database migrations 012–014 add the booking-product catalogue, member product choice (`not_yet_chosen` / `chosen` / `allocated` / `delivered`), multiple prizes per draw with quantities, draw-result rows, an atomic multi-prize execution RPC, and year-end fallback product allocation RPC.
- Dashboard now loads booking products, choices, draw prizes and results; member creation records a selected product or `NOT YET CHOSEN`; the Gifts page distinguishes draw prizes from booking products; Draw Management supports adding prize/quantity, executes multi-prize RPC, shows saved winners, and exposes year-end booking-product allocation.
- Added migration 013 and 014 locally; equivalent SQL was applied through the connected Supabase integration.
- `npm run check:release` passed after the source changes. ZIP archive integrity is tested after packaging.

## Not certified
- `npm ci` did not complete within the execution window; `next` executable is unavailable in this workspace, so `npm run build` could not run.
- No test draw was executed against real members because production data should not be modified as a test.
- Full browser E2E, RLS negative tests, payment/commission/payout integration, WhatsApp delivery/webhook, and legal/independent draw fairness certification remain unverified.
- Year-end allocation requires all 12 draws for the specified year to be configured and completed. It allocates selected booking products for non-winners; members marked `not_yet_chosen` remain pending and must choose before allocation.
- Existing `draws.winner_member_id` and legacy single-winner RPC remain for compatibility; multi-prize UI uses `execute_multi_prize_draw` and reads `draw_results`.
