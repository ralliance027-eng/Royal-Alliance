# Royal Alliance V21 — Multi-prize Draw Management

## UI changes
- Draw Management supports adding as many prize rows as needed to any configured month/year.
- Each prize row has a rank/order (1 = First Prize, 2 = Second Prize, 3 = Third Prize, etc.), a gift/product and winner quantity.
- Existing prize rows show Edit Prize and Remove controls until the draw is completed.
- Edit Prize updates the existing draw_prizes row by id; adding a prize upserts by (draw_id, gift_id).
- Edit Draw retains the selected month/year and other draw metadata; prize rows remain attached to the draw id.

## Validation
- `node scripts/validate-release.mjs`: PASS.
- This is static source validation only. A clean install, `next build`, browser E2E and live multi-winner execution have not been certified by this package.
