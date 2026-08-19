-- BALI STOCK 1.0.1: stable iPhone runtime backing storage.
-- The public object is a compiled runtime artifact only; source code remains in the private repository.
insert into storage.buckets (id, name, public)
values ('bali-stock-runtime', 'bali-stock-runtime', true)
on conflict (id) do update set public = excluded.public;
