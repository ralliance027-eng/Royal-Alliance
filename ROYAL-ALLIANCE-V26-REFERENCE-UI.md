# Royal Alliance V26 — Reference UI refresh

## What changed
- Updated shared application styling to align with the supplied Royal Alliance reference: deep emerald sidebar, gold active navigation, ivory canvas, emerald headings, gold accents, refined tables/cards/forms, and responsive mobile behavior.
- Because all authenticated dashboard sections share the same shell and component stylesheet, the visual refresh applies consistently across Overview, Admins, Agents, Members, Payments, Approvals, Cash Reconciliation, Commission & Referral, Payouts, Draw Management, Gifts & Products, Gift Delivery, WhatsApp Logs, Reports, Audit Logs, and Settings.
- Existing V25 manual/automatic WhatsApp source and migration retained.

## Validation
- `node scripts/validate-release.mjs`: PASS.
- ZIP integrity: to be verified after packaging.
- Production Next.js build, live browser E2E, screenshot pixel-match, and WhatsApp delivery: NOT certified in this package.

## Important limitation
The supplied reference is a montage/mockup, not individual page source files. This refresh applies a shared design system and does not claim pixel-perfect recreation of every small control or image shown in the montage. Workflow/data behavior was intentionally not rewritten as part of this visual pass.
