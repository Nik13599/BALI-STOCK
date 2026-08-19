-- BALI STOCK V16.1: safe product deletion from the active warehouse catalog.
-- Historical operation lines and catalog audit remain immutable.

create or replace function public.stock_catalog_product_delete_v17(
  p_product_key text,
  p_actor text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := nullif(trim(p_product_key), '');
  v_product public.stock_products%rowtype;
  v_before jsonb;
  v_balance bigint := 0;
  v_initialized boolean := false;
begin
  if v_key is null then
    raise exception 'product_key required';
  end if;

  select * into v_product
  from public.stock_products
  where product_key = v_key
  for update;

  if not found or v_product.active is not true then
    raise exception 'Товар не найден или уже удалён';
  end if;

  select coalesce(quantity_base, 0), initialized
    into v_balance, v_initialized
  from public.stock_balances
  where product_key = v_key;

  if coalesce(v_initialized, false) and coalesce(v_balance, 0) <> 0 then
    raise exception 'Нельзя удалить товар с ненулевым остатком. Сначала проведите переучёт и установите остаток 0.';
  end if;

  if exists (
    select 1
    from public.stock_location_balances b
    where b.product_key = v_key
      and b.initialized
      and coalesce(b.quantity_base, 0) <> 0
  ) then
    raise exception 'Нельзя удалить товар с ненулевым остатком по месту хранения. Сначала обнулите остаток переучётом.';
  end if;

  if exists (
    select 1
    from public.stock_draft_mirrors d
    cross join lateral jsonb_array_elements(coalesce(d.payload->'lines', '[]'::jsonb)) line
    where lower(trim(coalesce(line->>'product_name', ''))) = lower(trim(v_product.name))
      and coalesce(line->>'stock_unit', '') = v_product.stock_unit
      and coalesce(nullif(line->>'package_size', '')::integer, 0) = v_product.package_size
  ) then
    raise exception 'Товар есть в незавершённом переучёте. Сначала завершите или удалите соответствующий черновик.';
  end if;

  if exists (
    select 1
    from public.stock_purchase_request_lines l
    join public.stock_purchase_requests r on r.id = l.request_id
    where l.product_key = v_key
      and r.status in ('draft', 'confirmed', 'sent', 'partial')
  ) then
    raise exception 'Товар есть в активной заявке на закупку. Сначала завершите или отмените заявку.';
  end if;

  v_before := to_jsonb(v_product);

  delete from public.stock_location_balances where product_key = v_key;
  delete from public.stock_balances where product_key = v_key;
  update public.stock_product_suppliers
     set active = false, updated_at = now()
   where product_key = v_key;

  update public.stock_products
     set active = false,
         barcode = null,
         updated_at = now()
   where product_key = v_key;

  insert into public.stock_catalog_audit(action, product_key, actor, before_data, after_data)
  values(
    'catalog_product_delete',
    v_key,
    nullif(trim(p_actor), ''),
    v_before,
    jsonb_build_object(
      'product_key', v_key,
      'name', v_product.name,
      'category_name', v_product.category_name,
      'active', false,
      'deleted', true
    )
  );

  perform public.stock_bump_version();
  return true;
end
$$;

revoke all on function public.stock_catalog_product_delete_v17(text, text) from public, anon, authenticated;
grant execute on function public.stock_catalog_product_delete_v17(text, text) to service_role;
