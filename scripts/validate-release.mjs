import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = process.cwd();
const required = [
  'app/page.jsx', 'app/login/page.jsx', 'app/dashboard/page.jsx',
  'app/dashboard/[section]/page.jsx', 'lib/supabase.js',
  'supabase/functions/create-user/index.ts',
  'supabase/functions/send-whatsapp/index.ts',
  'supabase/migrations/202610090001_initial_schema.sql',
  'supabase/migrations/202610090011_payout_scope_guard.sql',
  'supabase/migrations/20261013150000_concurrent_member_registration_safety.sql',
  '.env.example', 'README.md', 'AUDIT-AND-NEXT-STEPS.md'
];
const errors = [];
for (const file of required) if (!fs.existsSync(path.join(root, file))) errors.push(`Missing required file: ${file}`);
const migrations = fs.readdirSync(path.join(root, 'supabase/migrations')).filter(f => /^\d{12}_.+\.sql$/.test(f)).sort();
if (migrations.length !== 15) errors.push(`Expected 15 numbered migrations, found ${migrations.length}`);
for (let i = 0; i < migrations.length; i++) {
  const expected = `20261009${String(i + 1).padStart(4, '0')}_`;
  if (!migrations[i].startsWith(expected)) errors.push(`Migration sequence gap/order issue near ${migrations[i]}`);
}
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
if (!pkg.scripts?.build) errors.push('package.json is missing the build script');
const supabaseClient = fs.readFileSync(path.join(root, 'lib/supabase.js'), 'utf8');
if (/SUPABASE_SERVICE_ROLE_KEY/.test(supabaseClient)) errors.push('Service role key reference found in browser Supabase client');
const approval = fs.readFileSync(path.join(root, 'supabase/migrations/202610090005_approve_payment_final.sql'), 'utf8');
for (const marker of ['office_cash_received', 'earnings_ledger', 'payment.approved', 'referred_count >= 2']) {
  if (!approval.includes(marker)) errors.push(`Payment approval invariant missing: ${marker}`);
}
const scopeGuard = fs.readFileSync(path.join(root, 'supabase/migrations/202610090011_payout_scope_guard.sql'), 'utf8');
for (const marker of ['guard_payout_team_scope', 'public.is_admin_of_agent', 'Member payout is outside your assigned team']) {
  if (!scopeGuard.includes(marker)) errors.push(`Payout scope invariant missing: ${marker}`);
}
const registration = fs.readFileSync(path.join(root, 'supabase/migrations/20261013150000_concurrent_member_registration_safety.sql'), 'utf8');
for (const marker of ['members_mobile_normalized_unique_idx', 'members_registration_request_unique_idx', 'register_member_idempotent', 'on conflict (registration_request_id) do nothing', 'members_normalize_mobile']) {
  if (!registration.toLowerCase().includes(marker.toLowerCase())) errors.push(`Concurrency safety invariant missing: ${marker}`);
}
const dashboard = fs.readFileSync(path.join(root, 'app/dashboard/page.jsx'), 'utf8');
if (!dashboard.includes("rpc('register_member_idempotent'")) errors.push('Member registration is not using the idempotent database RPC');
const whatsapp = fs.readFileSync(path.join(root, 'supabase/functions/send-whatsapp/index.ts'), 'utf8');
for (const marker of ['Payment is outside your assigned team', 'Winner is outside your assigned team']) {
  if (!whatsapp.includes(marker)) errors.push(`WhatsApp authorization invariant missing: ${marker}`);
}
if (errors.length) {
  console.error('Release validation FAILED');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}
console.log('Release validation PASSED');
console.log(`- ${required.length} required files present`);
console.log(`- ${migrations.length} numbered migrations present in sequence`);
console.log('- Payment approval, payout team-scope, and WhatsApp team-scope invariants found');
console.log('- Browser Supabase client contains no service-role key reference');
console.log('- Member registration uses idempotent RPC, atomic sequence-backed codes, and normalized-mobile uniqueness');
console.log('Note: this is a static source check, not a database integration or production build test.');
