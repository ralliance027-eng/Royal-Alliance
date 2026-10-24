# Deploy `create-user` Edge Function (Windows / PowerShell)

This is a cloud Supabase deployment; Docker is not a prerequisite for the normal remote Edge Function deployment flow.

1. Open PowerShell in this project directory.
2. Stop any stuck bundling command with `Ctrl+C`.
3. Check the CLI: `npx supabase --version`
4. Link the correct project (one time): `npx supabase link --project-ref ppsvxrvsgfnplsrnkubv`
5. Deploy with diagnostic output: `npx supabase functions deploy create-user --debug`
6. Wait for the explicit success message. If bundling remains stuck, use `Ctrl+C` and capture all output from the `--debug` command.
7. In Supabase Dashboard → Edge Functions → `create-user` → Logs, check the function invocation after a test submission.

The function imports `@supabase/supabase-js` through Deno's `npm:` specifier to avoid depending on the esm.sh URL in the source. The server must have the platform-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` secrets available. Never add the service-role key to `.env.local`, any `NEXT_PUBLIC_*` variable, or client code.

Admin creation uses `auth.admin.createUser({ email, password, email_confirm: true })`; it does not call `inviteUserByEmail`, so it does not send an invitation email. Only an authenticated active Super Admin can create Admin accounts. Test in a staging project first.

A deploy command is successful only when the CLI confirms deployment. Static source changes alone do not deploy the function to your Supabase project.
