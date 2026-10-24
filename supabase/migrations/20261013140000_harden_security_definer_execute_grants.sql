-- Harden exposed SECURITY DEFINER functions. Trigger functions remain executable by their owner when fired by PostgreSQL triggers.
REVOKE ALL ON FUNCTION public.approve_payment(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.build_draw_eligibility_snapshot(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_app_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.declare_draw_winner(uuid,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.execute_draw_selection(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.execute_multi_prize_draw(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_booking_product_allocation(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_member_winner_status() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_payout_team_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_auth_user_created() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_admin_of_agent(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_payout_paid(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prepare_member_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prepare_payment_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reconcile_cash_deposit(uuid,uuid[],text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_payment(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.request_member_referral_payout(uuid,numeric,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.request_payout(numeric,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_payout(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_agent_profile() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_draw_config(uuid,text,integer,integer,uuid,date) FROM PUBLIC, anon;

-- These business RPCs remain callable only by authenticated sessions. Each function also enforces application-role/team checks internally.
GRANT EXECUTE ON FUNCTION public.approve_payment(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.build_draw_eligibility_snapshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.declare_draw_winner(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.execute_draw_selection(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.execute_multi_prize_draw(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_booking_product_allocation(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin_of_agent(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_payout_paid(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_cash_deposit(uuid,uuid[],text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_payment(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_member_referral_payout(uuid,numeric,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_payout(numeric,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_payout(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_draw_config(uuid,text,integer,integer,uuid,date) TO authenticated;
