# Royal Alliance V47 — Premium Header, Overview & Multiple Draw UI

## Changes
- Premium dark-green / gold global top header with higher contrast breadcrumb, profile chip and mobile menu.
- Overview adds role-scoped quick insight cards for pending payments, draw schedule/prize assignments, and gifts/products.
- Draw Management explicitly presents the multiple-draw workflow and summary counts for draws, prize assignments, winner records, and upcoming/active draws.
- Each draw row lists multiple prize ranks and winner quantities from `draw_prizes`, with per-draw Add Prize action preselecting that draw.
- Existing Build Eligibility, Run Draw and Winner Register actions remain in place.
- Responsive layout adjustments for compact/mobile widths.

## Validation
`node scripts/validate-release.mjs` passed (required files, migration sequence, selected workflow markers, and no service-role key in browser client).

A clean dependency install, Next.js production build, browser visual comparison, and live Supabase integration were not run as part of this package.
