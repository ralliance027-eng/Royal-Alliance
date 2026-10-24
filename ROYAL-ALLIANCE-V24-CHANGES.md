# Royal Alliance V24 — Additive Completion Pass

This package is based on V23 and preserves existing files/features; it does not intentionally delete existing functionality.

## Added in V24
- Edit existing Draw Prize/Gift metadata and replace its image using the existing Royal Alliance Storage bucket.
- Edit existing Booking Product metadata, status, image URL, or upload a replacement image.
- Active/inactive state can be changed from edit forms rather than deleting records.
- Corrected the Gifts & Products explanatory copy to reflect the year-end fallback allocation RPC already present in the database.
- Added this implementation/verification note.

## Existing features retained
- Admin/Agent/Super Admin role panels and member/payment/payout workflows.
- No-member-login model.
- Multi-prize draw configuration with per-prize quantity.
- Booking product preference and NOT YET CHOSEN status.
- Storage bucket `royal-alliance-media` and image upload for gifts and booking products.
- Existing SQL migrations and Edge Functions.

## Verification performed
- `npm run check:release` passed before these UI-only edits.
- V23 archive integrity passed.
- This runtime did not complete `npm ci` within the allowed time, so V24 production build and browser E2E tests are not certified.
- Cloud migrations/functions are not automatically deployed by extracting this ZIP. The storage bucket and prior multi-prize/booking migrations were applied directly to the connected Supabase project in earlier steps.

## Known release gates (do not treat as complete until tested)
- `npm ci` and `npm run build` on a clean machine.
- Browser E2E for Admin creation/no invitation, Member creation, payment approval, ledger/commission/referral, payout settlement, draw eligibility/execution, product image upload/edit, and WhatsApp delivery.
- RLS negative tests for cross-agent/cross-admin access.
- Confirm approved referral scheme, draw terms, and applicable legal/regulatory requirements before live operation.
