# Fix: Member registration RPC not found

The screenshot error means PostgREST cannot see `public.register_member_idempotent(...)`.
The frontend calls this RPC by name; the SQL migration must be applied to the **same Supabase project** used by the local app.

## Apply the fix
1. Open Supabase Dashboard for the project whose URL/key are in the app's `.env.local`.
2. Open SQL Editor → New query.
3. Open `APPLY-V66-MEMBER-REGISTRATION.sql`, copy all SQL, and run it.
4. If it stops with the duplicate-normalized-mobile exception, do not delete/merge rows blindly. Review duplicate mobile groups first.
5. Confirm `public.register_member_idempotent` exists under Database → Functions (or run the verification query below).
6. The migration issues `NOTIFY pgrst, 'reload schema'`; wait a few seconds, refresh the local app, and try a test member.
7. Confirm the same registration retry does not create a second row and a duplicate normalized phone is rejected.

## Verification query
```sql
select n.nspname as schema_name, p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='register_member_idempotent';
```

## Important
This migration is intentionally fail-safe: it aborts if historical members contain normalized duplicate phone numbers. Resolve those records under an approved data-correction process before rerunning. Do not claim 100-agent certification until authenticated parallel-load tests pass.
