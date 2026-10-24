# Royal Alliance V71 — Sub-Agent Login on Member Assignment

## Changes
- The Assign Member dialog now has an optional checkbox to create a Sub-Agent login in the same workflow.
- When enabled, it asks for Sub-Agent name, email/login ID, mobile, and a password (minimum 10 characters).
- Account creation uses the protected `create-user` Edge Function. The function now accepts a parent Main Agent ID from authorized Super Admin/Admin flows, validates the active parent and enforces team scope; Main Agents can only create a Sub-Agent under themselves.
- Assignment still goes through `update_member_record`; database policy blocks reassignment if payment history exists.
- No password is written into profile or audit logs.

## Deployment notes
1. Deploy updated `supabase/functions/create-user/index.ts` to the correct Royal Alliance Supabase project, keeping JWT verification enabled and existing secrets configured.
2. Apply the existing `20261013180000_member_edit_assignment_workflow.sql` migration if not already applied. Do not blindly replay historical migrations; reconcile the live migration history first.
3. Run the app from this extracted project, restart Next.js, and hard refresh.
4. Test Super Admin, Admin (own team only), and Main Agent (self only) flows. Verify newly created account can sign in and member assignment succeeds only if no payment history exists.

Static release validation passed. A clean production build, live Edge Function deployment, and role-scoped E2E tests have not been confirmed by this package build.
