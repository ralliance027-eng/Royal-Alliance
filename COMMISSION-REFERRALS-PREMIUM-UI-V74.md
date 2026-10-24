# Royal Alliance V74 — Premium Commission & Referrals UI

## UI changes
- Premium dark-green/gold hero with account-scope explanation and eligible earnings summary.
- Four KPI cards for direct customers, direct Sub-Agents, first-level team customers, and 2% override eligibility.
- Separate earning summaries for 10% direct commission, 2% immediate-parent override, member referral earnings, and pending/reserved entries.
- Premium hierarchy explorer, legend, direct-parent scope notice, ledger type badges, responsive layout, and four commission-rule cards.
- Existing ledger rows, search, record detail interaction, and role-aware page title retained.

## Business rules displayed
- 10% direct commission goes to the Agent/Sub-Agent assigned to the member whose payment is approved.
- 2% override is limited to the immediate parent and only after at least two active direct Sub-Agents each have a directly assigned member.
- No override to grandparent/deeper ancestors.
- Member referral earnings remain a separate ledger type.

## Verification
- `npm run check:release`: PASS (static source validator).
- Production Next.js build: NOT RUN because installed `node_modules/.bin/next` is unavailable in this environment. Do not treat this as build-certified.
- UI must be run locally and checked at desktop and mobile widths before production release.
