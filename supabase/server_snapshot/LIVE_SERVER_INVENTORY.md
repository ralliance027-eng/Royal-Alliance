# Royal Alliance — Live server inventory snapshot

Captured: 2026-11-26 UTC  
Project ref: `ppsvxrvsgfnplsrnkubv`  
Region: `ap-south-1`  
PostgreSQL: `17.11.0.003`

## Database structure

- Public application tables: 21
- Public application tables with RLS enabled: 21/21
- SECURITY DEFINER functions in `public`: 28
- Storage buckets present: `prize-images` (public), `royal-alliance-kyc` (private), `royal-alliance-media` (public)

### Public tables

- `agents`
- `audit_logs`
- `booking_products`
- `cash_deposit_batches`
- `code_migration_history`
- `company_settings`
- `draw_eligible_members`
- `draw_prizes`
- `draw_results`
- `draws`
- `earnings_ledger`
- `gift_deliveries`
- `gifts`
- `member_booking_choices`
- `member_kyc_documents`
- `members`
- `notification_logs`
- `payment_entries`
- `payout_allocations`
- `payout_requests`
- `profiles`

### SECURITY DEFINER functions

- `approve_payment(p_payment_id uuid, p_reason text)`
- `build_draw_eligibility_snapshot(p_draw_id uuid)`
- `current_app_role()`
- `declare_draw_winner(p_draw_id uuid, p_member_id uuid)`
- `execute_draw_selection(p_draw_id uuid)`
- `execute_multi_prize_draw(p_draw_id uuid)`
- `finalize_booking_product_allocation(p_draw_year integer)`
- `guard_member_winner_status()`
- `guard_payout_team_scope()`
- `handle_auth_user_created()`
- `is_admin_of_agent(p_agent_id uuid)`
- `is_agent_in_tree(p_root uuid, p_candidate uuid)`
- `log_code_migration_change()`
- `mark_payout_paid(p_payout_id uuid, p_payment_reference text, p_notes text)`
- `prepare_member_insert()`
- `prepare_payment_insert()`
- `ra_next_agent_code()`
- `ra_next_member_code()`
- `reconcile_cash_deposit(p_agent_id uuid, p_payment_ids uuid[], p_receipt_number text, p_notes text)`
- `register_member_idempotent(p_address text, p_assigned_agent_id uuid, p_full_name text, p_installment_amount numeric, p_installment_frequency text, p_joining_date date, p_mobile text, p_nominee_name text, p_referred_by_code text, p_request_id uuid)`
- `reject_payment(p_payment_id uuid, p_reason text)`
- `request_member_referral_payout(p_member_id uuid, p_amount numeric, p_method text, p_account_reference text, p_notes text)`
- `request_payout(p_amount numeric, p_method text, p_account_reference text)`
- `review_payout(p_payout_id uuid, p_decision text, p_notes text)`
- `sync_agent_profile()`
- `update_draw_config(p_draw_id uuid, p_title text, p_month integer, p_year integer, p_gift_id uuid, p_draw_date date)`
- `update_member_record(p_member_id uuid, p_full_name text, p_mobile text, p_address text, p_nominee_name text, p_nominee_mobile text, p_joining_date date, p_installment_amount numeric, p_installment_frequency text, p_assigned_agent_id uuid)`

## Deployed Edge Function snapshot

- Function: `create-user`
- Version: `6`
- Status: `ACTIVE`
- JWT verification: enabled
- SHA-256: `71cc7d45df562eb36b51d310153b7f49594f76ee55f8151554a73735f08b7d3e`
- Exact source and deployed CORS helper captured under `functions/create-user/`.

## Important source/server distinction

The deployed `create-user` function is an exact snapshot of what was live at capture time. It uses wildcard CORS (`Access-Control-Allow-Origin: *`) and is stored here for comparison/forensics only. The candidate function under `supabase/functions/create-user/` is the revised source in the working ZIP and is not proof of what is deployed. Do not deploy the candidate until the production origin allowlist is configured and tested.

## Migration reconciliation warning

See `MIGRATION_LEDGER_LIVE.txt`. Live ledger contains 39 records; the working ZIP now contains 39 SQL migration files. The exact `20261027063542 | renumber_existing_agent_and_member_codes` body was recovered from the live database execution-history table `supabase_migrations.schema_migrations.statements` (3,048 characters; MD5 `0e2e64f2a03073012ee9f0d719f59fb0`) and restored as a migration file. Other filename/version drift remains and must be reconciled before `db reset` or blind `db push`.
