# Royal Alliance V66 — Concurrent member registration hardening

## Changes
- Member IDs continue to use PostgreSQL `nextval()` sequences, which are atomic under concurrent inserts; `members.member_code` remains unique.
- Added a unique normalized-mobile index so formatting variants such as `98765 43210` and `+91 98765-43210` cannot create duplicate Indian mobile records.
- Migration intentionally aborts if historical records already contain duplicate normalized phone groups. Resolve those records explicitly; it never merges or deletes members automatically.
- Added `registration_request_id` uniqueness and `register_member_idempotent(...)`. A retried submission with the same UUID returns the original member row rather than creating another member.
- Registration RPC retains the existing role/team trigger checks and adds scope checks when returning an idempotent result.
- Member creation UI now calls the RPC and upserts the booking-choice row, so retrying after a network interruption does not create a second booking choice.
- Database constraints remain the final race-condition guard; client validation is not relied on for uniqueness.

## Deployment
1. Back up the connected Supabase project.
2. Reconcile the repository migrations with the remote migration history first; do not replay the baseline migrations blindly.
3. Apply `supabase/migrations/20261013150000_concurrent_member_registration_safety.sql` to the correct Royal Alliance project.
4. If it aborts due to historical normalized-mobile duplicates, inspect the reported groups and decide the correct business resolution before retrying.
5. Deploy this frontend release after the migration is applied. The updated UI requires the `register_member_idempotent` RPC.

## Certification status
Static source validation can verify that the protections are present. It cannot prove 100 simultaneous authenticated registrations without a controlled staging project and 100 authorized agent sessions. Run that test against staging using unique test phone numbers, then verify: 100 unique member IDs, 100 distinct member rows, zero duplicate normalized phones, zero duplicate request results, correct assigned-agent scope, and no duplicate booking-choice rows. Do not run synthetic registrations against production member data.
