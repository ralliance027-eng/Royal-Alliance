# Royal Alliance — security and concurrency audit (2026-10-13)

## Live Supabase project checked
- Project ref: `ppsvxrvsgfnplsrnkubv`
- Status: `ACTIVE_HEALTHY`
- Region: `ap-south-1`
- PostgreSQL: 17.11
- Live migration history: 17 rows returned by Supabase Management API.
- Live Edge Functions: `create-user` active; `send-whatsapp` was not present in the live function list at audit time.

## Changes applied to live database
1. Revoked `PUBLIC` and `anon` EXECUTE privileges on exposed SECURITY DEFINER functions. Trigger functions also have direct EXECUTE revoked from authenticated; PostgreSQL triggers still invoke them as trigger functions.
2. Kept authenticated EXECUTE only on intended workflow RPCs. The RPCs retain their internal role/team checks; this grant change does not replace RLS or function-level authorization.
3. Added indexes for public-schema foreign keys that had no covering index.

## Post-change verification
- Privilege query: all audited SECURITY DEFINER functions now report `anon_exec=false` and `public_exec=false`.
- Authenticated EXECUTE remains on intended RPC functions; trigger functions are not directly executable by application roles.
- Supabase Security Advisor no longer reports `anon_security_definer_function_executable` after privilege change. It still reports 15 `authenticated_security_definer_function_executable` warnings (these require per-function review; authenticated access was preserved for intended app RPCs).
- Performance Advisor no longer reports `unindexed_foreign_keys` after indexes were added.
- Remaining Advisor warnings: leaked-password protection is disabled; 16 RLS auth-initplan warnings; 6 multiple-permissive-policy warnings; some unused-index informational notices.

## Not certified
- Clean `npm ci` did not finish within the available command timeout; production `npm run build` was therefore not completed.
- No browser-based page-by-page E2E suite or 100-concurrent-user load test was run.
- No payment/commission/payout/draw race-condition test was run against staging with controlled test data.
- `send-whatsapp` deployment/live delivery is not certified.
- Do not claim 100-user capacity or production readiness until these checks pass.
