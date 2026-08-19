-- V15 purchase request workflow. Applied to production on 2026-08-19.
-- Expands request statuses and tracks delivery progress against request lines.

alter table public.stock_purchase_request_lines
  add column if not exists received_quantity bigint not null default 0;

alter table public.stock_purchase_requests
  drop constraint if exists stock_purchase_requests_status_check;

alter table public.stock_purchase_requests
  add constraint stock_purchase_requests_status_check
  check (status in ('draft','confirmed','sent','partial','completed','cancelled'));

create or replace function public.stock_set_purchase_request_status(
  p_id uuid,
  p_status text,
  p_employee text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_status not in ('draft','confirmed','sent','partial','completed','cancelled') then
    raise exception 'invalid request status';
  end if;
  update public.stock_purchase_requests
     set status=p_status,
         updated_at=now(),
         comment=case when nullif(trim(p_employee),'') is null then comment
                      else concat_ws(E'\n',comment,'Статус изменил: '||trim(p_employee)) end
   where id=p_id;
  if not found then raise exception 'purchase request not found'; end if;
  perform public.stock_bump_version();
end $$;

create or replace function public.stock_purchase_delivery_progress()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  req_id uuid;
  current_status text;
  all_done boolean;
begin
  if new.change_quantity <= 0 then return new; end if;

  select nullif(metadata->>'purchase_request_id','')::uuid
    into req_id
    from public.stock_operations
   where id=new.operation_id
     and operation_type='delivery';

  if req_id is null then return new; end if;

  select status into current_status
    from public.stock_purchase_requests
   where id=req_id;
  if current_status is null or current_status='cancelled' then return new; end if;

  update public.stock_purchase_request_lines
     set received_quantity=least(requested_quantity,received_quantity + new.change_quantity)
   where request_id=req_id
     and product_key=new.product_key;

  select coalesce(bool_and(received_quantity >= requested_quantity),false)
    into all_done
    from public.stock_purchase_request_lines
   where request_id=req_id;

  update public.stock_purchase_requests
     set status=case when all_done then 'completed' else 'partial' end,
         updated_at=now()
   where id=req_id;

  return new;
end $$;

drop trigger if exists trg_stock_purchase_delivery_progress on public.stock_operation_lines;
create trigger trg_stock_purchase_delivery_progress
after insert on public.stock_operation_lines
for each row execute function public.stock_purchase_delivery_progress();

revoke all on function public.stock_purchase_delivery_progress() from public, anon, authenticated;
grant execute on function public.stock_purchase_delivery_progress() to service_role;

revoke all on function public.stock_set_purchase_request_status(uuid,text,text) from public, anon, authenticated;
grant execute on function public.stock_set_purchase_request_status(uuid,text,text) to service_role;
