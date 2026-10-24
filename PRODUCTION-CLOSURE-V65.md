# Royal Alliance V65 — production closure status (2026-10-13)

## Completed and verified
- `node scripts/validate-release.mjs` passes: 12 required files, 15 numbered baseline migrations, key source invariants, no browser service-role key reference.
- Live Supabase function privileges hardened: anonymous/PUBLIC EXECUTE removed from audited SECURITY DEFINER functions; intended authenticated workflow RPCs preserved; trigger functions are not directly executable by app roles.
- Added covering indexes for previously unindexed public-schema foreign keys. Supabase Performance Advisor no longer reports `unindexed_foreign_keys`.
- Live database is `ACTIVE_HEALTHY` (PostgreSQL 17.11, ap-south-1).

## Remaining release gates — do not represent as passed
1. Authenticated SECURITY DEFINER warnings (15): inspect each RPC implementation and prove role/team checks with negative tests. Some RPCs must remain callable by authenticated app users.
2. Leaked-password protection: enable in Supabase Dashboard → Authentication → Security and password settings. This setting is not safely adjustable through the connected database SQL API.
3. RLS performance: 16 auth-initplan warnings and 6 multiple-permissive-policy warnings. Rewrite policies only after comparing exact intended access matrix; a blanket policy rewrite risks changing data visibility.
4. `npm ci`: attempted with a 120-second command limit but timed out. `npm run build` consequently not run.
5. Browser E2E for Super Admin/Admin/Agent, including cross-team and cross-role denial tests.
6. Controlled 100-user load test and financial concurrency tests on staging/test data (duplicate payment approval, commission idempotency, payout balance reservation, same-draw double execution).
7. WhatsApp live delivery: only `create-user` was found deployed; `send-whatsapp` not present at audit time. Requires approved function source, secrets, deployment, and a real consented test number.
8. Reconcile local and remote migration histories before any future migration deployment. The live migration API showed 17 entries, while the local baseline and hardening migrations differ in naming/count. Do not blindly replay them.

## Run locally
- `npm ci`
- `npm run check:release`
- `npm run build`

Build passing is not proof of 100-user capacity. Use a staging project with synthetic data for all load/race tests; do not load-test financial RPCs against live customer records.
