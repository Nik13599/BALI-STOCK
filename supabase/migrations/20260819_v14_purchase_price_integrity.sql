-- V14 purchase-price integrity.
-- Last purchase price and its currency are authoritative delivery facts.
-- Catalog editing and supplier linking must never overwrite them.

create or replace function public.stock_catalog_products_batch_v14(p_items jsonb, p_actor text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  item jsonb;
  new_key text;
  result jsonb := '[]'::jsonb;
  before_meta jsonb;
  after_meta jsonb;
  prior_cost numeric;
  prior_currency text;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'items required';
  end if;

  for item in select value from jsonb_array_elements(p_items) loop
    prior_cost := null;
    prior_currency := 'BYN';
    select to_jsonb(p), p.default_cost, p.cost_currency
      into before_meta, prior_cost, prior_currency
      from public.stock_products p
      where p.product_key = nullif(trim(item->>'old_product_key'),'');

    new_key := public.stock_catalog_product_upsert_v3(
      nullif(trim(item->>'old_product_key'),''),
      item->>'name',
      item->>'category_name',
      coalesce((item->>'category_sort')::integer,0),
      greatest(coalesce((item->>'package_size')::integer,1),1),
      coalesce(nullif(trim(item->>'stock_unit'),''),'ml'),
      coalesce((item->>'minimum_amount')::bigint,0),
      coalesce((item->>'target_amount')::bigint,0),
      nullif(trim(coalesce(item->>'barcode','')),''),
      prior_cost,
      coalesce(prior_currency,'BYN'),
      coalesce((item->>'variance_recheck_amount')::bigint,0),
      coalesce((item->>'active')::boolean,true),
      p_actor
    );

    update public.stock_products set
      sell_by_bottle = coalesce((item->>'sell_by_bottle')::boolean, sell_by_bottle),
      bottle_sale_price = case when item ? 'bottle_sale_price' then nullif(item->>'bottle_sale_price','')::numeric else bottle_sale_price end,
      portion_sale = coalesce((item->>'portion_sale')::boolean, portion_sale),
      portion_prices = case when item ? 'portion_prices' then coalesce(item->'portion_prices','[]'::jsonb) else portion_prices end,
      image_path = case when item ? 'image_path' then nullif(trim(coalesce(item->>'image_path','')),'') else image_path end,
      updated_at = now()
    where product_key = new_key;

    select to_jsonb(p) into after_meta from public.stock_products p where p.product_key = new_key;
    insert into public.stock_catalog_audit(action,product_key,actor,before_data,after_data)
      values('product_v14_batch',new_key,p_actor,before_meta,after_meta);

    result := result || jsonb_build_array(jsonb_build_object(
      'old_product_key', item->>'old_product_key',
      'product_key', new_key
    ));
  end loop;

  return result;
end
$function$;

create or replace function public.stock_link_product_supplier(
  p_product_key text,
  p_supplier uuid,
  p_sku text default null::text,
  p_price numeric default null::numeric,
  p_currency text default 'BYN'::text,
  p_primary boolean default false
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if p_primary then
    update public.stock_product_suppliers set is_primary=false where product_key=p_product_key;
  end if;

  -- p_price/p_currency remain in the signature for backward compatibility,
  -- but manual supplier linking does not own purchase-price facts.
  insert into public.stock_product_suppliers(product_key,supplier_id,supplier_sku,last_price,currency,is_primary,active,updated_at)
  values(p_product_key,p_supplier,p_sku,null,'BYN',p_primary,true,now())
  on conflict(product_key,supplier_id) do update set
    supplier_sku=excluded.supplier_sku,
    is_primary=excluded.is_primary,
    active=true,
    updated_at=now();

  perform public.stock_bump_version();
end
$function$;

create or replace function public.stock_apply_delivery_v2(
  p_employee text,
  p_lines jsonb,
  p_supplier uuid default null::uuid,
  p_document_number text default null::text,
  p_comment text default null::text,
  p_attachment_url text default null::text,
  p_location uuid default null::uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  op uuid;
  item jsonb;
  p public.stock_products%rowtype;
  b public.stock_balances%rowtype;
  lb public.stock_location_balances%rowtype;
  added bigint;
  after_q bigint;
  loc uuid;
  cost numeric(14,4);
  currency text;
  total numeric(16,4):=0;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then raise exception 'delivery lines required'; end if;
  loc:=coalesce(p_location,public.stock_primary_location_id());
  if loc is null then raise exception 'stock location required'; end if;

  insert into public.stock_operations(operation_type,employee_name,completed_at,created_at,supplier_id,document_number,comment,attachment_url,target_location_id,metadata,total_value)
    values('delivery',nullif(trim(p_employee),''),now(),now(),p_supplier,nullif(trim(p_document_number),''),nullif(trim(p_comment),''),p_attachment_url,loc,coalesce(p_metadata,'{}'::jsonb),0)
    returning id into op;

  for item in select value from jsonb_array_elements(p_lines) loop
    select * into p from public.stock_products where product_key=item->>'product_key' and active=true for update;
    if not found then raise exception 'unknown product %',item->>'product_key'; end if;
    select * into b from public.stock_balances where product_key=p.product_key for update;
    if not b.initialized or b.quantity_base is null then raise exception 'initial stocktake required for %',p.name; end if;

    added:=coalesce((item->>'quantity_base')::bigint,0);
    if added<=0 then raise exception 'delivery quantity must be positive'; end if;
    cost:=nullif(item->>'unit_cost','')::numeric;
    if cost is null then raise exception 'purchase price required for %',p.name; end if;
    if cost < 0 then raise exception 'purchase price cannot be negative for %',p.name; end if;
    currency:=coalesce(nullif(trim(item->>'currency'),''),'BYN');

    after_q:=b.quantity_base+added;
    update public.stock_balances set quantity_base=after_q,initialized=true,updated_at=now() where product_key=p.product_key;
    perform public.stock_ensure_location_balance(loc,p.product_key);
    select * into lb from public.stock_location_balances where location_id=loc and product_key=p.product_key for update;
    update public.stock_location_balances set quantity_base=coalesce(lb.quantity_base,0)+added,initialized=true,updated_at=now() where location_id=loc and product_key=p.product_key;

    insert into public.stock_operation_lines(operation_id,product_key,product_name,category_name,package_size,stock_unit,before_quantity,before_initialized,change_quantity,after_quantity,unit_cost,line_value,target_location_id,metadata)
      values(op,p.product_key,p.name,p.category_name,p.package_size,p.stock_unit,b.quantity_base,true,added,after_q,cost,(added::numeric/nullif(p.package_size,0))*cost,loc,coalesce(item->'metadata','{}'::jsonb));
    total:=total+((added::numeric/nullif(p.package_size,0))*cost);

    update public.stock_products set default_cost=cost,cost_currency=currency,updated_at=now() where product_key=p.product_key;
    if p_supplier is not null then
      insert into public.stock_product_suppliers(product_key,supplier_id,last_price,currency,updated_at)
      values(p.product_key,p_supplier,cost,currency,now())
      on conflict(product_key,supplier_id) do update set last_price=excluded.last_price,currency=excluded.currency,active=true,updated_at=now();
    end if;
  end loop;

  update public.stock_operations set total_value=total where id=op;
  perform public.stock_bump_version();
  return op;
end
$function$;
