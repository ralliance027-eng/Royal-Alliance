# Royal Alliance V38 — Role-scoped Reports

## Report visibility
- Super Admin: company-wide reporting, Admin Reports, all agents and members, collections, payments, commissions/referrals, payouts, draws, gifts, WhatsApp logs and activity logs.
- Admin: own assigned team reporting; agents are restricted to agents where `admin_id` matches the logged-in admin. Members/payments and team-linked logs are scoped to the visible team data. No Admin Reports tab.
- Agent: only own assigned members, their payments, agent/member earnings and payouts scoped to own member/agent IDs, own member winner records, and related WhatsApp/activity records. No company-wide agent list, gift configuration, or unrelated members/agents.

## Technical changes
- Added role-scoped data sets and report row filtering in `app/dashboard/ReportsDashboard.jsx`.
- Agent dashboard collection chart now uses scoped payments rather than the full visible payment list.
- Agent reports tab now shows their own performance instead of an empty/global agent list.
- Quick Agent/Member report preview and export use scoped report data.

## Verification
- `npm run check:release`: PASS.
- TypeScript JSX transpile syntax diagnostics: 0.
- ZIP integrity: checked after packaging.
- Production build and authenticated browser/RLS E2E: NOT RUN; do not treat as certified.
