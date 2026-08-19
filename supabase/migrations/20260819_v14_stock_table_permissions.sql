-- Defense in depth for the warehouse schema.
-- RLS already limits client roles to read policies; remove write grants as well.

do $block$
declare
  r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relname like 'stock_%'
  loop
    execute format('revoke insert, update, delete, truncate, references, trigger on table public.%I from anon', r.relname);
    execute format('revoke insert, update, delete, truncate, references, trigger on table public.%I from authenticated', r.relname);
    execute format('grant all on table public.%I to service_role', r.relname);
  end loop;
end
$block$;
