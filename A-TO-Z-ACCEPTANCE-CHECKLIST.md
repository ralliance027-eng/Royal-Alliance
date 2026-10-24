# A-to-Z acceptance checklist

Check an item only after it is tested against a real staging Supabase project.

- [ ] Login/logout/password recovery
- [ ] Role redirects and disabled account rejection
- [ ] Super Admin: admin create/edit/activate/deactivate
- [ ] Admin: agent create/edit/activate/deactivate and team scope
- [ ] Agent: own member create/edit/search and ownership protection
- [ ] Member IDs and referral codes unique
- [ ] Payment entry always starts PENDING
- [ ] Approval/rejection and audit trail
- [ ] Cash reconciliation batch totals match approved cash entries
- [ ] Payment reversal/refund ledger behavior
- [ ] Exactly-once 10% agent commission
- [ ] 2% referral eligibility after two valid referrals
- [ ] Referral self/duplicate prevention
- [ ] Payout request/approval/paid reference and balance reconciliation
- [ ] Duplicate payout and concurrent settlement rejection
- [ ] 12 draws configured by month/year
- [ ] Winner selection logged and prior winners excluded
- [ ] Gift delivery status lifecycle
- [ ] WhatsApp templates, consent, send/delivery/failure/retry logs
- [ ] Dashboard metrics match SQL aggregates
- [ ] Date/status/search filters
- [ ] CSV export and verified PDF/Excel export if advertised
- [ ] Company settings permission and audit history
- [ ] Cross-agent RLS negative tests
- [ ] Cross-admin/team RLS negative tests
- [ ] Clean install (`npm ci`)
- [ ] Release validation (`npm run check:release`)
- [ ] Production build (`npm run build`)
- [ ] Browser E2E and mobile responsive tests
- [ ] Backup/restore and deployment rollback tested
