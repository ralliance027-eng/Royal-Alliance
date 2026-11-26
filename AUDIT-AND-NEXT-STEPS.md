# Royal Alliance — implementation and verification report

## Completed in the supplied source package
- Removed `.env.local` and Supabase `.temp` project metadata from the release package.
- Added `.env.example` and `.gitignore`.
- Pinned direct package dependency versions in `package.json`.
- Replaced wildcard CORS with exact-origin allow-list logic in shared Edge Function code.
- Fixed the duplicate `source_member_id` property in `create-user` and added rollback of newly created Auth users if profile/audit setup fails.
- Reworked `send-whatsapp` authorization for Admin, Agent, and Sub-Agent member/agent team scope; added provider timeout and a `sent_unconfirmed` state for accepted messages whose log update fails.
- Updated Dashboard, operational sections, and report filters so Sub-Agents use their own scoped workspace labels/filters and can open the member WhatsApp action.
- Added a signed Meta webhook handler for WhatsApp sent/delivered/read/failed status reconciliation.
- Added append-only code-change history triggers for member and agent code changes.
- Restricted `ra_next_agent_code()` and `ra_next_member_code()` from browser RPC execution.
- Replaced duplicate permissive RLS policies with separate read/write policies and added missing FK indexes.
- Added RLS init-plan optimization for policies that call `auth.uid()` and `current_app_role()`.
- Reworked release validator for 14-digit migration names, unique versions, current function checks, and sensitive-file exclusion.

## Live Supabase changes applied and verified
Project: `ppsvxrvsgfnplsrnkubv` (`ralliance Project`)
- `code_migration_history`: RLS enabled; only active Super Admin can read through authenticated client policy; client writes revoked; service role retains backend access.
- Member and Agent code-change triggers installed.
- `ra_next_agent_code()` and `ra_next_member_code()` are no longer executable by `anon` or `authenticated` roles.
- Duplicate permissive policies removed from Agents, Booking Products, Company Settings, Draw Eligibility, Draw Prizes, Draw Results, and Gifts.
- Missing `agents.parent_agent_id` and `members.parent_agent_id` indexes added; duplicate `members_agent_idx` removed.
- RLS expressions optimized to use scalar subqueries for auth/current-role lookups.
- `notification_logs` now supports `sent_unconfirmed`; provider message ID index added.
- Manual WhatsApp handoff RLS policy extended to Sub-Agents with direct hierarchy scope checks.
- Live migration ledger now includes the new security/performance/WhatsApp schema migrations.

## Verification performed
- Supabase project status: `ACTIVE_HEALTHY`.
- Live `code_migration_history` RLS enabled and Super Admin-only SELECT policy verified.
- Code-change triggers exist on `public.members` and `public.agents`.
- Anonymous and authenticated execute privileges for both sequence helper RPCs verified false.
- Supabase performance advisor no longer reports unindexed foreign keys, duplicate indexes, multiple permissive policies, or auth RLS init-plan warnings. Remaining unused-index notices are informational and expected on an empty development database.
- TypeScript compiler syntax pass produced no TS1xxx syntax diagnostics for the Edge Functions; missing Deno/npm type packages prevented a full type-check.
- TypeScript JSX parse pass produced no diagnostics for the application JSX files.
- Live database verification: all 21 public tables have RLS enabled; 2 code-history triggers exist; the Super Admin is the only remaining Auth/profile account after reset.

## Still pending (not credential values themselves)
1. **Migration reconciliation:** 39 remote ledger entries vs 39 local SQL files after this recovery; only 11 exact timestamp matches. The `20261027063542` SQL was recovered verbatim from the live database migration execution history (`supabase_migrations.schema_migrations.statements`) and added at `supabase/migrations/20261027063542_renumber_existing_agent_and_member_codes.sql`. Other historical filename/version drift remains; do not run `db reset` or blind `db push` until all versions are reconciled.
2. **npm lockfile and full build:** package registry access timed out and dependencies were not available offline. `package-lock.json`, `npm ci`, `npm run build`, and `npm audit` remain unverified.
3. **CORS origin configuration and Edge Function deployment:** set `APP_ALLOWED_ORIGINS` to the exact production domain(s), then deploy updated `create-user`, `send-whatsapp`, and `whatsapp-webhook` functions. The live project currently exposes `create-user` v6 only; no `send-whatsapp` function is listed. No real app domain was present in the uploaded ZIP, so the functions were not redeployed with a guessed origin.
4. **WhatsApp webhook activation:** code is included; deployment and Meta callback subscription require the WhatsApp verify token/app secret and provider configuration.
5. **Auth leaked-password protection:** Supabase Auth advisor still reports this setting disabled; it must be enabled in Auth password/security settings.
6. **Security-definer advisories:** 18 authenticated-callable `SECURITY DEFINER` functions remain intentionally available for protected RPC workflows. Their function bodies contain role checks, and `anon` execution is revoked. Supabase's generic advisor still flags authenticated execution; do not blanket-revoke these without mapping every frontend RPC and policy dependency.
7. **End-to-end business tests:** no real Agent/Sub-Agent users, members, payment entries, or WhatsApp provider credentials remain after the clean reset. Full workflow tests require seeded staging data and credentials.

## Release status
Source-level hardening and several live database fixes are complete. This is **not production-certified** until the migration ledger is reconciled, dependencies/build are verified, origins and Edge Functions are configured/deployed, Auth password protection is enabled, and role-based E2E tests pass.

## 2026-11-26 live-server capture addendum

A server snapshot was added under `supabase/server_snapshot/` after querying the connected live Supabase project.

- Exact deployed `create-user` Edge Function v6 source and its deployed `_shared/cors.ts` helper are included for comparison/forensics.
- The live Supabase migration ledger (39 version/name records) is included in `MIGRATION_LEDGER_LIVE.txt`.
- A structural inventory of the 21 public tables, 28 SECURITY DEFINER functions, RLS coverage and storage buckets is included in `LIVE_SERVER_INVENTORY.md`.
- The exact SQL for `20261027063542 | renumber_existing_agent_and_member_codes` was recovered from the live database execution-history table `supabase_migrations.schema_migrations` (`statements` field), verified as 3,048 characters / MD5 `0e2e64f2a03073012ee9f0d719f59fb0`, and restored into the ZIP. It was not reconstructed or guessed.
- Existing historical migration SQL files were not edited in the live project. Seven new migrations dated 2026-11-26 were applied; see the exact ledger.
- The exact deployed `create-user` function currently has wildcard CORS. It is preserved as a server snapshot and is not substituted for the hardened candidate function under `supabase/functions/create-user/`.

Do not run `supabase db reset` or blindly `db push` until the remaining historical migration filename/version drift is reconciled.


## Recovery update — 2026-11-26
- Recovered the original `renumber_existing_agent_and_member_codes` SQL directly from the live Supabase `supabase_migrations.schema_migrations.statements` record for version `20261027063542`.
- Exact-source fingerprint: 3,048 characters; MD5 `0e2e64f2a03073012ee9f0d719f59fb0`; rollback field is null in the server history.
- Added as `supabase/migrations/20261027063542_renumber_existing_agent_and_member_codes.sql`. No live database changes were made during this recovery.


## Next.js build TypeScript exclusion fix (2026-11-26)
- Updated `tsconfig.json` `exclude` to include `supabase/server_snapshot/**`.
- Retained the existing `supabase/functions/**` exclusion.
- This prevents the archived/deployed Deno Edge Function source under `supabase/server_snapshot/` from being type-checked as part of the Next.js application build.
- The Deno import `npm:@supabase/supabase-js@2` in the snapshot was intentionally left unchanged; it is valid in the Deno Edge Function environment and is not a Next.js dependency import.
- `package.json` dependencies and versions were preserved without changes.
- Build execution was not performed in this packaging step; run `npm run build` in the project environment.


## Anaira developer micro-branding (2026-11-26)
- Added the supplied Anaira logo as a compact circular brand mark at `public/images/anaira-brand-mark.png`.
- Added restrained `Powered by Anaira Graphics & Digital Solution` attribution on the login screen and authenticated dashboard footer.
- Added clickable `tel:+919736500084` and `tel:+919736589984` contact links and `https://graphics.anairapos.in` website link.
- Added developer attribution metadata while preserving Royal Alliance as the application/product brand.
- Existing Royal Alliance logo, name, workflows, Supabase configuration and migrations were not changed by this branding update.
- Branding is compact and responsive; no large promotional banner or customer-brand replacement was added.
- Build execution was not performed during ZIP packaging; run `npm run build` in the target environment.


## Anaira micro-branding contact and sizing revision (2026-11-26)
- Corrected the second contact number to `9736580084`; the two displayed numbers are `9736500084` and `9736580084`.
- Updated both `tel:` links to `tel:+919736500084` and `tel:+919736580084` respectively.
- Increased the compact Anaira logo mark slightly for better visibility while reducing the developer-credit text and footer spacing.
- Kept the Anaira attribution at the end of the login content and authenticated dashboard content, without competing with Royal Alliance branding.


## Anaira branding link and icon refinement (2026-11-26)
- Added a phone icon before each clickable call number and a globe icon before the website link.
- Made the `Anaira Graphics` name clickable, opening a Google Maps business search for Anaira Graphics & Digital Solution, Akhara Bazar, Kullu, Himachal Pradesh.
- The Maps link is a business search URL, not a verified direct Google Business Profile share URL; replace with the exact GBP share link if supplied by the business owner.


## Complete in-app notification centre implementation (2026-11-26)
- Added migration `20261126050000_complete_in_app_notification_centre.sql` creating role-scoped `app_notifications`, own-row RLS, event routing triggers, indexes, and Realtime publication membership.
- Added bell dropdown with unread badge, latest 40 notifications, mark-read, mark-all-read, and Realtime INSERT/UPDATE subscription scoped to the signed-in user's own rows.
- Added optional browser desktop alerts while the app is open and the browser permission is granted. This is not a closed-browser Web Push service worker.
- Trigger events: member created, agent created, payment submitted/approved/rejected, payout requested/status changed, draw completed, and gift delivery status changed.
- WhatsApp send/delivery logs remain in the existing WhatsApp Notifications section; they are not duplicated into the in-app notification feed automatically.
- Migration must be applied to Supabase before the centre can receive database-triggered notifications. Existing historical events are not backfilled.
- Validate actual role/tenant recipient mapping against production data before production rollout.

- Payment status transition routing explicitly covers both `approved` and `rejected`; the SQL derives the event key from the new status.
- This ZIP includes the migration source but does not apply it to the live Supabase database.
