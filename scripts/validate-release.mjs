import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = process.cwd();
const required = [
  'app/page.jsx', 'app/login/page.jsx', 'app/dashboard/page.jsx',
  'app/dashboard/[section]/page.jsx', 'lib/supabase.js',
  'supabase/functions/create-user/index.ts',
  'supabase/functions/send-whatsapp/index.ts',
  'supabase/functions/whatsapp-webhook/index.ts',
  'supabase/functions/_shared/cors.ts',
  'supabase/migrations/20261009000100_initial_schema.sql',
  'supabase/migrations/20261126042940_code_migration_audit_and_sequence_access.sql',
  'supabase/migrations/20261126043034_policy_deduplication_and_fk_indexes.sql',
  'supabase/migrations/20261126043351_whatsapp_manual_subagent_scope.sql',
  '.env.example', 'README.md', 'AUDIT-AND-NEXT-STEPS.md'
];
const errors = [];
const warnings = [];
for (const file of required) if (!fs.existsSync(path.join(root, file))) errors.push(`Missing required file: ${file}`);
const migrationDir = path.join(root, 'supabase/migrations');
const migrations = fs.readdirSync(migrationDir).filter(f => /^\d{14}_.+\.sql$/.test(f)).sort();
if (migrations.length < 2) errors.push(`Expected 14-digit timestamp migrations, found ${migrations.length}`);
const versions = new Set();
for (const file of migrations) {
  const version = file.slice(0, 14);
  if (versions.has(version)) errors.push(`Duplicate migration version: ${version}`);
  versions.add(version);
}
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
if (!pkg.scripts?.build) errors.push('package.json is missing the build script');
if (!pkg.engines?.node) errors.push('Node engine requirement is missing');
if (!fs.existsSync(path.join(root, 'package-lock.json'))) warnings.push('package-lock.json is not present; npm registry was unavailable during this review, so a reproducible lockfile could not be generated.');
const supabaseClient = fs.readFileSync(path.join(root, 'lib/supabase.js'), 'utf8');
if (/SUPABASE_SERVICE_ROLE_KEY/.test(supabaseClient)) errors.push('Service role key reference found in browser Supabase client');
const cors = fs.readFileSync(path.join(root, 'supabase/functions/_shared/cors.ts'), 'utf8');
if (/Access-Control-Allow-Origin['"]\s*:\s*['"]\*['"]/.test(cors)) errors.push('Wildcard CORS origin is configured');
for (const file of ['supabase/functions/create-user/index.ts','supabase/functions/send-whatsapp/index.ts']) {
  const source = fs.readFileSync(path.join(root,file),'utf8');
  if (!source.includes('isOriginAllowed(req)')) errors.push(`${file} does not enforce origin allow-list`);
}
const createUser = fs.readFileSync(path.join(root,'supabase/functions/create-user/index.ts'),'utf8');
const profileUpdateLine = createUser.match(/const profileUpdate:[^\n]+/);
if (!profileUpdateLine || (profileUpdateLine[0].match(/source_member_id:/g)||[]).length !== 1) errors.push('create-user profile update must set source_member_id exactly once');
if (!createUser.includes('createdUserId') || !createUser.includes('rollbackError')) errors.push('create-user rollback path missing');
const dashboard = fs.readFileSync(path.join(root,'app/dashboard/page.jsx'),'utf8');
const operational = fs.readFileSync(path.join(root,'app/dashboard/OperationalSections.jsx'),'utf8');
const reports = fs.readFileSync(path.join(root,'app/dashboard/ReportsDashboard.jsx'),'utf8');
if (!dashboard.includes("'sub_agent'") || !operational.includes("'sub_agent'") || !reports.includes("'sub_agent'")) errors.push('Sub-Agent dashboard/report access paths are missing');
const whatsapp = fs.readFileSync(path.join(root,'supabase/functions/send-whatsapp/index.ts'),'utf8');
for (const marker of ['assertMemberScope','assertAgentScope','is_agent_in_tree','consent_confirmed','AbortSignal.timeout']) {
  if (!whatsapp.includes(marker)) errors.push(`WhatsApp authorization/reliability invariant missing: ${marker}`);
}
const codeAudit = fs.readFileSync(path.join(root,'supabase/migrations/20261126042940_code_migration_audit_and_sequence_access.sql'),'utf8');
for (const marker of ['enable row level security','log_code_migration_change','members_log_code_migration','agents_log_code_migration','ra_next_agent_code','ra_next_member_code']) {
  if (!codeAudit.toLowerCase().includes(marker.toLowerCase())) errors.push(`Code migration audit invariant missing: ${marker}`);
}
for (const forbidden of ['.env.local','supabase/.temp/']) if (fs.existsSync(path.join(root,forbidden))) errors.push(`Sensitive/local file must not ship: ${forbidden}`);
if (errors.length) {
  console.error('Release validation FAILED');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}
console.log('Release validation PASSED');
console.log(`- ${required.length} required files present`);
console.log(`- ${migrations.length} unique 14-digit timestamp migrations found`);
console.log('- CORS allow-list, create-user rollback, WhatsApp team-scope, and code-history invariants found');
console.log('- No browser service-role key reference or local secrets in the release package');
console.log('Note: static source validation only; production build and authenticated E2E tests are separate.');
for (const warning of warnings) console.warn(`WARNING: ${warning}`);
