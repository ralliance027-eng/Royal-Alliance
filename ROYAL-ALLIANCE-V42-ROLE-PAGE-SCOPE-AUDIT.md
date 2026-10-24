# Royal Alliance V42 — Role-wise page and data scope audit

## Findings in V41 source
- Navigation listed operational sections (`agents`, `members`, `payments`, `approvals`, `cash`, `earnings`, `payouts`, `draws`, `gifts`, `deliveries`, `whatsapp`, `audit`), but the main Dashboard JSX rendered only Overview, Admins, Reports and Settings. The other URLs therefore had no actual section body.
- Agent commission/payout loader filters relied mainly on `beneficiary_profile_id` / `requested_by_profile_id`; rows using `beneficiary_agent_id`, `agent_id`, or `beneficiary_profile_id` variants could be omitted from the correct user's view.
- Audit scope did not consistently include activity records tied to a scoped payment or payout ID.

## V42 changes
- Added `OperationalSections.jsx` and wired all listed operational sections into the dashboard renderer.
- Members, payments, approval queues, cash reconciliation, earnings, payouts, draw schedule/winner register, gifts, delivery, WhatsApp logs, and audit logs render using the role-scoped data passed by the main dashboard.
- Agent view labels explicitly indicate own members/payments/earnings/payouts and only winners among their own members. Draw calendar remains shared company configuration; agent winner results remain scoped.
- Added search/filter controls to operational tables and actions wired to existing handlers (payment approval, payout review, cash reconciliation, draw eligibility/execution, delivery status, manual member WhatsApp, notification retry).
- Expanded earnings and payout scope predicates to include agent/profile foreign-key variants. Expanded audit scope to include authorized payment/payout entity IDs.
- Non-super-admin data state no longer includes raw company settings.

## Checks performed
- TypeScript transpile/parser diagnostics for `app/dashboard/page.jsx`, `app/dashboard/OperationalSections.jsx`, and `app/dashboard/ReportsDashboard.jsx`: PASS.
- `npm run check:release`: PASS.
- ZIP integrity: checked after packaging.

## Not certified
- Full `next build` and browser end-to-end tests were not run.
- UI filtering is not a substitute for Supabase RLS. Live cross-tenant negative tests are still required for every relevant table/RPC.
- Draw calendar, prize catalogue and booking products are shared company configuration where the existing workflow expects shared configuration; member-level winner/financial records are scoped.
