# Royal Alliance V69 — Member Edit & Assignment Workflow

## UI
- Members table now shows **Edit**, **Assign**, and **WhatsApp** actions on each member row.
- Clicking **Edit** opens a pre-filled form for member details and assigned Agent/Sub-Agent.
- Clicking **Assign** opens a focused assignment form showing the member code/name and current assignment.
- Super Admin can assign to any active Agent/Sub-Agent.
- Admin can assign to active Agent/Sub-Agent accounts in their admin team.
- Main Agent can assign to itself or its own active Sub-Agents.
- Sub-Agent can only keep/assign members to its own account.

## Database migration
Apply `supabase/migrations/20261013180000_member_edit_assignment_workflow.sql` after the V68 hierarchy migration. It creates `public.update_member_record(...)`, checks caller role/team scope, records an audit event, preserves member codes/referral codes, and rejects duplicate mobile numbers.

For financial integrity, reassignment is blocked once the member has any payment history. This avoids changing the agent attribution of old payments/commissions. Profile edits remain available.

## Validation
- TypeScript JSX parser syntax check: PASS.
- `node scripts/validate-release.mjs`: PASS.
- Production Next.js build and live role/RLS E2E were not run in this packaging pass.
- The V68 hierarchy migration and this V69 migration must both be applied before the new UI can successfully use Sub-Agent assignments.
