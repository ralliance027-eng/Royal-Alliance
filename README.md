# Royal Alliance Annual Member Draw Management System

## Current source package
This package contains the Next.js application, Supabase migrations, and Supabase Edge Functions for Royal Alliance Multiventure Services Pvt. Ltd.

### Implemented application areas
- Login via Supabase Auth and role-based workspace routing.
- Overview dashboard, Admin/Agent profiles, Members, payment entry and approval.
- Office cash reconciliation, commission/referral ledger, payouts and member-referral payout workflow.
- Monthly draws, gift catalog, winner declaration, gift delivery, WhatsApp logs, reports, audit logs, and program settings.
- Deep-link routes for all dashboard areas: `/dashboard/members`, `/dashboard/payments`, `/dashboard/approvals`, `/dashboard/cash`, `/dashboard/earnings`, `/dashboard/payouts`, `/dashboard/draws`, `/dashboard/gifts`, `/dashboard/deliveries`, `/dashboard/whatsapp`, `/dashboard/reports`, `/dashboard/audit`, `/dashboard/settings`, `/dashboard/agents`, and `/dashboard/admins`.

## Local setup
1. Install Node.js 20+.
2. Copy `.env.example` to `.env.local` and set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (or legacy NEXT_PUBLIC_SUPABASE_ANON_KEY)`.
3. Apply Supabase migrations in numeric order `202610090001` through `202610090011` to a **staging** project first. Do not skip earlier migrations.
4. Deploy the `create-user` and `send-whatsapp` Edge Functions. Configure their required secrets only in Supabase, never in browser environment variables.
5. Run `npm install`, then `npm run dev`; verify login, permissions, each workflow and database policies. Run `npm run check:release` for the repeatable static release checks.
6. Run `npm run build` in a clean environment before deployment.

## Important status
This is a development source package, not a production-certified release. The source ZIP can be integrity-checked, but this environment could not complete `npm install` within the available time, so a production build and database execution have **not** been certified here. Apply migrations only to staging first and test role isolation, concurrent receipt reconciliation, payout allocation, draw eligibility, payout team scope, and WhatsApp failure handling before real financial use.

## Financial rules
Defaults are 10% agent commission, 2% member referral income after at least two valid referrals, and 12 monthly draws. Confirm the written company scheme and applicable legal requirements before operating any prize draw/referral-income program.


## V69 Member Edit & Assignment
See `MEMBER-EDIT-ASSIGN-V69.md`. Members table provides Edit and Assign actions for authorized roles. Apply V68 hierarchy migration before V69 assignment RPC migration.


## V73 Commission & Referrals chain update
See `COMMISSION-REFERRALS-CHAIN-V73.md` for hierarchy, direct-parent commission scope, member-to-Sub-Agent promotion, and migration/deployment steps. Apply the V73 migration only after the V72 hierarchy migration.


## V77 commission rule update (packaged, not deployed)
See `V77-DIRECT-PARENT-10-GRANDPARENT-2-COMMISSION.md` and migration `supabase/migrations/20261019130000_direct_parent_10pct_grandparent_2pct.sql`. This changes future approvals so the direct parent gets 10% and the parent of that parent gets 2%. The migration is not yet applied to live Supabase.

## V79 — Sub-Agent 2% qualification
Migration `20261027120000_subagent_override_requires_three_active_members.sql` is applied to the connected Royal Alliance Supabase project. For future approvals, the hierarchy 2% override is only credited when the intended override beneficiary has at least three active members assigned directly to that profile. Two or fewer means no hierarchy 2% ledger entry. The separate Member Referral 2% rule remains unchanged (at least two qualifying referred members with approved payment history). Existing ledger entries are not recalculated.


## V80 Commission rule update (migration packaged; live deployment must be verified)
See `V80-COMMISSION-RULES.md` and `supabase/migrations/20261027150000_v80_direct_10_parent_2_active_subagents.sql`. 10% goes to the collector; 2% goes only to the immediate parent if that parent has at least two active direct Sub-Agent children.
