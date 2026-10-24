# V72 implementation status

This ZIP is built from the V71 project source and includes the V72 unlimited hierarchy implementation.

Implemented in source:
- Arbitrary branch size and nested parent_agent_id hierarchy for Agent/Sub-Agent accounts.
- Sub-Agent can create another Sub-Agent beneath themselves.
- Descendant team scope in dashboard data loading.
- Parent/child-aware member creation and registration RPC.
- Approved-payment commission logic: collector gets 10%; each eligible ancestor gets a 2% override if they have at least two active direct Sub-Agents and each of those branches contains at least one member at any depth.
- Ledger idempotency by commission type, payment, and beneficiary to avoid duplicate payouts on retries while allowing multiple ancestors to be credited.
- Existing admin approval and cash reconciliation checks remain in payment approval.

Before production:
1. Back up database and reconcile migration history.
2. Apply migrations in order, including V68 hierarchy migration and `20261014120000_unlimited_agent_tree_and_qualified_override.sql`.
3. Deploy `supabase/functions/create-user/index.ts` to the connected project with JWT verification enabled.
4. Run staged end-to-end tests for nested creation, commission qualification, duplicate approval/retry, payout balances, and RLS/team isolation.

Validation performed:
- `scripts/validate-release.mjs`: PASS (static source validation).
- ZIP integrity: to be checked at package creation.
- No live DB migration or 100-user load test is claimed by this ZIP.
