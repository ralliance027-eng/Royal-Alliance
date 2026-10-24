-- Add a leading-column index for each public-schema foreign key that does not already have one.
-- Safe to re-run: existing covering indexes are detected and indexes use IF NOT EXISTS.
DO $$
DECLARE r record; idx_name text;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass AS tbl,
           c.conname,
           c.conkey,
           t.relname AS table_name,
           string_agg(quote_ident(a.attname), ', ' ORDER BY u.ord) AS col_list,
           array_agg(a.attnum ORDER BY u.ord) AS col_nums
    FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    JOIN LATERAL unnest(c.conkey) WITH ORDINALITY u(attnum,ord) ON true
    JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=u.attnum
    WHERE c.contype='f' AND n.nspname='public'
    GROUP BY c.oid,t.relname,c.conname,c.conkey
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_index i
      WHERE i.indrelid = r.tbl AND i.indisvalid AND i.indisready
        AND (SELECT array_agg(k ORDER BY ord)
             FROM unnest(i.indkey::smallint[]) WITH ORDINALITY x(k,ord)
             WHERE ord <= cardinality(r.col_nums)) = r.col_nums
    ) THEN
      idx_name := left('idx_fk_'||r.table_name||'_'||regexp_replace(r.conname,'_fkey$',''), 60);
      EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %s (%s)', idx_name, r.tbl, r.col_list);
    END IF;
  END LOOP;
END $$;
