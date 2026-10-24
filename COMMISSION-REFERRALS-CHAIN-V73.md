# Royal Alliance V73 — Commission & Referrals Chain

## Implemented in source
- Commission & Referrals page now includes a recursive Agent/Sub-Agent tree, direct-member counts, direct-child counts, first-level team-member counts, override eligibility summary, and a commission ledger with payment reference, basis amount, rate, earning type, beneficiary, and status.
- Tree rendering is depth-limited defensively to 30 levels in the UI; database hierarchy and creation remain recursive/unlimited subject to cycle protection in the database helpers.
- Member → Assign can promote a member to a Sub-Agent login. Name/mobile are prefilled; the operator enters login email and password. The new profile stores `source_member_id` to link back to the original member. The member is assigned to the new Sub-Agent account.
- Promotion is blocked in the UI if that member already has payment history because the current assignment RPC locks reassignment to preserve payment and commission audit attribution.
- The `create-user` Edge Function validates that the source member is directly assigned to the selected parent before linking it.
- New migration replaces the all-ancestor override logic with direct-parent-only 2% override: only the immediate parent can receive it, and only when at least two active direct Sub-Agents each have at least one directly assigned member. Grandparents and deeper ancestors do not receive override on that payment.
- 10% commission remains with the assigned collector; member referral earnings remain a separate ledger type. Existing payment approval and audit workflow is preserved in the replacement function.

## Apply order
1. Ensure V72 migration `20261014120000_unlimited_agent_tree_and_qualified_override.sql` is applied first.
2. Apply `supabase/migrations/20261016100000_direct_scope_commission_and_member_promotion.sql` to the intended Royal Alliance Supabase project.
3. Deploy the updated `supabase/functions/create-user/index.ts` Edge Function after the migration is applied. Keep JWT verification enabled and do not expose service-role secrets in the browser.
4. Restart Next.js and refresh the browser. Open Commission & Referral from the sidebar.

## Important verification notes
- Static release validator and TypeScript JSX transpile syntax checks passed.
- `npm ci` timed out in this environment, so a production `next build` was not completed.
- This ZIP's new V73 migration and Edge Function are not claimed as deployed to live Supabase. Test member promotion, nested Sub-Agent creation, RLS isolation, direct-parent override eligibility, referral eligibility, and duplicate approval behavior in staging before production use.
