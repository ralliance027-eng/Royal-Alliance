# Royal Alliance V68 — Sub-Agent Hierarchy & Commission

## Included
- Main Agent can create Sub-Agent login through protected `create-user` Edge Function.
- Sub-Agent is stored as `profiles.role = 'sub_agent'` with `parent_agent_id`; matching `agents` row receives an agent code.
- Main Agent can create member records for itself or its own active Sub-Agents; Sub-Agent can create only its own members.
- Payment approval remains Admin/Super Admin only and retains the existing cash reconciliation checks.
- Approved Sub-Agent payment: 10% to Sub-Agent and 2% override to parent Main Agent. Regular Agent payment remains 10% only. Existing member referral rule remains separately recorded.
- Earnings ledger unique key expanded to include beneficiary, allowing the two agent commission rows without duplicate payouts on retries.
- Audit log captures both agent commission amounts.

## Migration
`supabase/migrations/20261013170000_sub_agent_hierarchy_commissions.sql`

Apply only after reviewing the connected database and taking a backup. The project schema was inspected against `ppsvxrvsgfnplsrnkubv` (`ralliance Project`). The migration file is included in this ZIP; it has **not** been applied to production as part of this artifact build.

## Login creation
Deploy updated `supabase/functions/create-user/index.ts` as the `create-user` Edge Function. A Main Agent can create a Sub-Agent account. This function creates active accounts with the entered password and does not send an invitation email; share credentials securely.

## Validation notes
- Static JavaScript/JSX syntax checks and release checks should be run after install.
- No real Sub-Agent login or financial transaction was created as part of packaging.
- Must test in staging: role scopes, direct and Sub-Agent member assignment, pending/rejected payments, cash reconciliation, approved 10%+2% ledger entries, duplicate approval retry, payout availability, and cross-agent access denial.
