-- Cover stock foreign keys used by deliveries, history, catalog deletion and invoice cleanup.
create index if not exists stock_invoice_scan_lines_product_key_idx
  on public.stock_invoice_scan_lines (product_key);
create index if not exists stock_invoice_scan_lines_scan_id_idx
  on public.stock_invoice_scan_lines (scan_id);
create index if not exists stock_invoice_scans_operation_id_idx
  on public.stock_invoice_scans (operation_id);
create index if not exists stock_invoice_scans_supplier_id_idx
  on public.stock_invoice_scans (supplier_id);
create index if not exists stock_location_balances_product_key_idx
  on public.stock_location_balances (product_key);
create index if not exists stock_operation_lines_source_location_id_idx
  on public.stock_operation_lines (source_location_id);
create index if not exists stock_operation_lines_target_location_id_idx
  on public.stock_operation_lines (target_location_id);
create index if not exists stock_operations_correction_of_idx
  on public.stock_operations (correction_of);
create index if not exists stock_operations_source_location_id_idx
  on public.stock_operations (source_location_id);
create index if not exists stock_operations_supplier_id_idx
  on public.stock_operations (supplier_id);
create index if not exists stock_operations_target_location_id_idx
  on public.stock_operations (target_location_id);
create index if not exists stock_purchase_request_lines_product_key_idx
  on public.stock_purchase_request_lines (product_key);
create index if not exists stock_purchase_request_lines_request_id_idx
  on public.stock_purchase_request_lines (request_id);
create index if not exists stock_purchase_requests_supplier_id_idx
  on public.stock_purchase_requests (supplier_id);

-- These read RPCs are called by service-role Edge Functions, not public clients.
revoke all on function public.stock_analytics_summary(integer) from public, anon, authenticated;
revoke all on function public.stock_primary_location_id() from public, anon, authenticated;
revoke all on function public.stock_purchase_suggestions() from public, anon, authenticated;

grant execute on function public.stock_analytics_summary(integer) to service_role;
grant execute on function public.stock_primary_location_id() to service_role;
grant execute on function public.stock_purchase_suggestions() to service_role;
