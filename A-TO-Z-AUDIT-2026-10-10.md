# Royal Alliance A-to-Z Source Audit — V16

Audit target: Royal Alliance Annual Member Draw Management Software
Audit date: 2026-10-10
Source reviewed: V15 ZIP and its application/migration files.

## Verified from source
- Next.js app has four route files: `/`, `/login`, `/dashboard`, and `/dashboard/[section]`.
- The dashboard contains 16 section keys: overview, admins, agents, members, payments, approvals, cash, earnings, payouts, draws, gifts, deliveries, whatsapp, reports, audit, settings.
- 11 SQL migration files are included (001–011).
- Supabase browser client supports `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` and legacy `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- `package.json` exposes `dev`, `build`, `start`, and `check:release` scripts.

## Not certified
These are not marked complete because the current environment has not run the application against the actual Supabase project:
- Clean dependency install and production build
- Applying all migrations against staging/production Supabase
- Authentication and role lifecycle for real users
- RLS negative tests for cross-agent and cross-admin data access
- Member create/edit/search and ownership constraints
- Payment entry, approval/rejection, reversal/refund, and cash reconciliation
- Exactly-once commission and referral ledger calculations
- Payout approval, transaction reference, and duplicate-settlement prevention
- Draw eligibility, random selection auditability, winner exclusion, and gift delivery
- WhatsApp provider delivery, retries, approved templates, and consent
- Reports/CSV/PDF/Excel exports and totals reconciliation
- Browser end-to-end, responsive UI, and regression tests

## Scope note
The 39 entries in the product description are a planning inventory, not 39 independent route files. The current code consolidates the UI into one dashboard component and routes the 16 dashboard sections through a dynamic route. This may be acceptable architecture, but each section still needs its own acceptance tests and complete workflow verification.

## Release gate
Do not describe this build as 100% production-complete until:
1. `npm ci` succeeds from a clean checkout.
2. `npm run check:release` passes.
3. `npm run build` passes.
4. Migrations 001–011 apply cleanly to a staging database.
5. Role/RLS tests prove isolation for Super Admin, Admin, and Agent.
6. Financial and draw workflows pass integration tests with duplicate/replay and failure scenarios.
7. Live WhatsApp is verified using approved templates and consented test numbers.
8. All unresolved critical/high findings are closed and the acceptance checklist is signed off.

## How to continue
- Copy `.env.example` to `.env.local` locally and use the correct Supabase project URL and publishable key.
- Never commit `.env.local` or service-role secrets.
- Use a staging project and synthetic records first. Do not run unreviewed migrations against production data.
