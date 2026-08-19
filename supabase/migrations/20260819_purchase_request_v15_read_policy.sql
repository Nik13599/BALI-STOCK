-- Purchase requests are already exposed as read-only stock data by the BALI STOCK snapshot.
-- V15 mobile/desktop clients may read the two request tables directly, but all writes
-- remain restricted to the PIN-protected Edge API/service role.

drop policy if exists stock_purchase_requests_read on public.stock_purchase_requests;
create policy stock_purchase_requests_read
on public.stock_purchase_requests
for select
to anon, authenticated
using (true);

drop policy if exists stock_purchase_request_lines_read on public.stock_purchase_request_lines;
create policy stock_purchase_request_lines_read
on public.stock_purchase_request_lines
for select
to anon, authenticated
using (true);

grant select on public.stock_purchase_requests to anon, authenticated;
grant select on public.stock_purchase_request_lines to anon, authenticated;

revoke insert, update, delete, truncate, references, trigger
on public.stock_purchase_requests from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
on public.stock_purchase_request_lines from anon, authenticated;
