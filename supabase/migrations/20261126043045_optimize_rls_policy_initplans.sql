-- Avoid per-row repeated auth/current-role evaluation in public RLS policies.
do $$
declare
  r record;
  using_sql text;
  check_sql text;
begin
  for r in
    select p.polname, c.oid::regclass as relation_name,
           pg_get_expr(p.polqual,p.polrelid) as using_expr,
           pg_get_expr(p.polwithcheck,p.polrelid) as check_expr
    from pg_policy p
    join pg_class c on c.oid=p.polrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and (coalesce(pg_get_expr(p.polqual,p.polrelid),'') ~ 'auth\.uid\(\)|current_app_role\(\)'
        or coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'') ~ 'auth\.uid\(\)|current_app_role\(\)')
  loop
    using_sql := r.using_expr;
    check_sql := r.check_expr;
    if using_sql is not null then
      using_sql := replace(using_sql, 'auth.uid()', '(select auth.uid())');
      using_sql := regexp_replace(using_sql, '(^|[^.[:alnum:]_])current_app_role\(\)', '\1(select public.current_app_role())', 'g');
    end if;
    if check_sql is not null then
      check_sql := replace(check_sql, 'auth.uid()', '(select auth.uid())');
      check_sql := regexp_replace(check_sql, '(^|[^.[:alnum:]_])current_app_role\(\)', '\1(select public.current_app_role())', 'g');
    end if;
    if using_sql is not null and check_sql is not null then
      execute format('alter policy %I on %s using (%s) with check (%s)',r.polname,r.relation_name,using_sql,check_sql);
    elsif using_sql is not null then
      execute format('alter policy %I on %s using (%s)',r.polname,r.relation_name,using_sql);
    elsif check_sql is not null then
      execute format('alter policy %I on %s with check (%s)',r.polname,r.relation_name,check_sql);
    end if;
  end loop;
end $$;
