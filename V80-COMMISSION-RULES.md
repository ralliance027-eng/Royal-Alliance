# Royal Alliance V80 — Commission Rules

- **10% direct commission:** paid to the Agent/Sub-Agent assigned to the paying member. It never passes to the parent.
- **2% hierarchy override:** paid only to the collector's immediate parent (parent may be Agent or Sub-Agent), and only when that parent has at least two active direct Sub-Agent children (`profiles.parent_agent_id = parent.id`, `role = 'sub_agent'`, `status = 'active'`).
- No grandparent or deeper ancestor receives hierarchy override for that payment.
- Member referral 2% remains a separate earning type and keeps its own existing qualification rule.
- Existing earning ledger rows are not deleted or recalculated; this migration affects future payment approvals.

## Apply
Apply `supabase/migrations/20261027150000_v80_direct_10_parent_2_active_subagents.sql` to the intended Supabase project after reviewing it and taking a database backup.
