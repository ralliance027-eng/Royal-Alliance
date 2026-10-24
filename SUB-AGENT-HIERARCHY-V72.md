# Royal Alliance V72 — Unlimited Agent Tree

## Implemented in source
- Unlimited-depth parent_agent_id chain: an Agent or Sub-Agent can create a child Sub-Agent. An Agent/Sub-Agent can register members for self or direct child.
- Each node can have any number of direct children and members.
- Member/agent UI data scope expands through the whole descendant tree.
- Payment approval keeps the existing Admin/Super Admin approval gate and cash reconciliation checks.
- 10% goes to the collector. 2% override is recorded for each ancestor whose own direct child set has at least two active Sub-Agents and each qualifying branch contains at least one member at any depth.
- Commission ledger idempotency is changed to key each earning by type, payment and beneficiary, so multiple ancestor overrides can be credited without duplicate retry entries.
- Existing member referral 2% logic remains separate.

## Deployment order
1. Back up the Supabase database.
2. Review/apply `supabase/migrations/20261014120000_unlimited_agent_tree_and_qualified_override.sql` after the V68 hierarchy migration.
3. Deploy `supabase/functions/create-user/index.ts` as the `create-user` Edge Function (JWT verification enabled).
4. Run staging tests before production: 3+ levels, variable child counts, active-child qualification, branches without members, approved vs pending payments, duplicate approval/retry, admin team isolation, and cycle-prevention checks.

## Important
The SQL migration is packaged but has not been applied to the live database by this ZIP build. Static validation does not certify live RLS, payouts, browser E2E, or concurrent load. The helper caps recursive traversal at 100 levels as a defensive safeguard; normal team size is not limited.
