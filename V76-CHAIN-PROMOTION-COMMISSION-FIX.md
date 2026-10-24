# Royal Alliance V76 — Chain, Promotion & Commission Scope

## Changes
- `create-user` source updated so an Agent **or Sub-Agent** may create a Sub-Agent directly beneath their own account.
- Member-to-Sub-Agent login creation links `profiles.source_member_id` to the existing member. The member ID, assigned agent, and payment history remain unchanged.
- The promotion form no longer reassigns the existing member to the new Sub-Agent; it reports success only after the account-creation function succeeds.
- `approve_payment` pays 10% to the collector and, when qualified, 2% only to the collector's immediate parent. No grandparent/deeper ancestor override is created.
- The parent's eligibility requires at least two active direct Sub-Agents, each with at least one member anywhere in its descendant branch.
- Member referral earning remains a separate ledger type.

## Deployment state
- Database migration `direct_scope_commission_and_member_promotion_v76` was applied to the connected Royal Alliance Supabase project.
- A follow-up migration `fix_override_eligibility_for_descendant_members_v76` was applied to correct branch qualification.
- Live Edge Function `create-user` is now Version 4 with nested Sub-Agent parent support and `source_member_id` profile linking enabled. A further deploy that adds source-member ownership and duplicate-promotion validation was blocked; the stricter validation is present in this ZIP source but is not confirmed live.
- Static release validation passed. Production build and authenticated end-to-end tests have not run.

## Manual next step
Deploy `supabase/functions/create-user/index.ts` to the Royal Alliance project with JWT verification enabled, then test: member promotion, Sub-Agent creating a child Sub-Agent, child registering a member, payment approval, and duplicate retry behavior.
