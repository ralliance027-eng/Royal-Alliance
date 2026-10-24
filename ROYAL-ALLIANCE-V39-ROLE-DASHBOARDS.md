# Royal Alliance V39 — Role-separated dashboards

## Changes
- Super Admin overview is company-wide and includes admin count plus company totals.
- Admin overview uses only assigned agents, their members and related payments/earnings/payouts/operations.
- Agent overview uses only that agent's assigned members and related records; KPI labels are agent-specific.
- Agent quick actions no longer show payment review or gift management actions.
- Dashboard data is scoped in the client data loader before rendering sections and reports. This is defense-in-depth UI scoping; Supabase RLS remains the authoritative security boundary.
- Recent payment table uses the already scoped member list.

## Validation
- `npm run check:release`: PASS.
- TypeScript JSX transpile syntax check for `app/dashboard/page.jsx`: PASS (0 diagnostics).
- ZIP integrity: to be checked after packaging.
- Production build, browser role-by-role E2E and cross-tenant negative tests: NOT RUN.
