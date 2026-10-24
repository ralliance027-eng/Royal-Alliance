# Royal Alliance source audit — V15 configuration/security hardening package

## Included in this package
- Supabase migrations `202610090001` through `202610090011` (run in numeric order).
- Login configuration now accepts `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (and legacy `NEXT_PUBLIC_SUPABASE_ANON_KEY`).
- `.env.local` containing project configuration has been excluded from the distributable ZIP; use `.env.example` to create your local file.
- Login, role-based dashboard and current dashboard modules for Admins, Agents, Members, Payments, Payment Approval, Cash Reconciliation, Commission/Referral, Payouts, Draws, Gifts, Gift Delivery, WhatsApp Logs, Reports, Audit Logs and Settings.
- Added direct dashboard routes so each module can be opened/bookmarked independently, with role-based UI route checks.
- Existing Supabase Edge Functions for protected user invitations and WhatsApp dispatch.

## Checks performed in this environment
- ZIP source extracted successfully.
- TypeScript compiler parse/type-syntax pass was run on the app JSX entry files with `tsc --noEmit --allowJs --checkJs false --jsx preserve`; no compiler output/errors.
- `npm install --offline` could not proceed because required packages are not cached. Online `npm install` timed out in this environment.
- Consequently `next build` was not run and no Supabase migration was executed against a live/staging database.

## Not certified
This package is not represented as a production-certified release. UI/JSX syntax checks do not prove the Supabase schema, RLS, RPCs, payout accounting, draw fairness, or live WhatsApp integration are correct. Before real data or money is used:
1. Set `.env.local` using `.env.example` (never expose service-role keys in the browser).
2. Apply migrations `001` to `011` to a staging Supabase project in numeric order.
3. Deploy/configure Edge Functions and their secrets in Supabase.
4. Run `npm install` and `npm run build` in a network-enabled clean environment.
5. Execute positive and negative end-to-end tests for each role, cross-agent isolation, cash receipts, payment approval, commission/referral earnings, payout allocations, draw/winner exclusion, gift delivery and WhatsApp retries.
6. Resolve all database/build/test errors before production deployment.

- Added migration `011` to enforce Admin team scope when payout status transitions are made, including member referral payouts.
- WhatsApp Edge Function checks that an Admin's payment/winner belongs to their assigned team before dispatch.

## Known implementation boundary
The current app presents core modules as dashboard sections/routes. This does not imply every one of the 39 proposed planning items is a separate, independently implemented workflow. Member-level referral payouts are admin-managed because Members do not log in. Company policy and applicable Indian legal/regulatory requirements for prize draws/referral-income schemes must be reviewed before use.


## Current certification status
- Static release validation: PASS.
- Numbered migration inventory: 11 files, 001–011.
- Supabase publishable-key environment name: supported by the browser client.
- Secret/config hygiene: `.env.local` excluded from distributable ZIP.
- Production build: NOT VERIFIED (dependency installation did not complete in this environment).
- Live Supabase migration/RLS and role-based end-to-end tests: NOT RUN.
- WhatsApp live delivery: NOT CERTIFIED.
- Therefore this is a development/hardening package, not a claim of 100% production completion.
