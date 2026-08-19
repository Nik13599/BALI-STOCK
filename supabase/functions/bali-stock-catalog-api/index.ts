import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(url, serviceKey, { auth: { persistSession: false } });

function sanitizeCatalogItem(raw: any) {
  const item = { ...(raw ?? {}) };
  delete item.default_cost;
  delete item.cost_currency;
  const name = String(item.name ?? "").trim();
  const category = String(item.category_name ?? "").trim();
  const unit = String(item.stock_unit ?? "ml");
  const packageSize = Math.max(1, Number(item.package_size ?? 1));
  if (!name) throw new Error("Название товара обязательно");
  if (!category) throw new Error("Категория обязательна");
  if (!["ml", "g", "pcs"].includes(unit)) throw new Error("Неверная единица учёта");
  if (!Number.isFinite(packageSize) || packageSize <= 0) throw new Error("Неверный размер упаковки");
  return {
    ...item,
    name,
    category_name: category,
    package_size: Math.round(packageSize),
    stock_unit: unit,
    minimum_amount: Math.max(0, Number(item.minimum_amount ?? 0)),
    target_amount: Math.max(0, Number(item.target_amount ?? 0)),
    variance_recheck_amount: Math.max(0, Number(item.variance_recheck_amount ?? 0)),
    active: item.active !== false,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "catalog_product_batch") {
      const items = Array.isArray(body.items) ? body.items.map(sanitizeCatalogItem) : [];
      if (!items.length) throw new Error("Не выбраны изменения каталога");
      const { data, error } = await db.rpc("stock_catalog_products_batch_v14", {
        p_items: items,
        p_actor: String(body.employee ?? "").trim() || null,
      });
      if (error) throw error;
      return json({ ok: true, count: items.length, results: data ?? [] });
    }

    if (action === "product_upsert") {
      const item = sanitizeCatalogItem(body);
      const { data, error } = await db.rpc("stock_catalog_product_upsert_v3", {
        p_old_key: item.old_product_key ?? null,
        p_name: item.name,
        p_category_name: item.category_name,
        p_category_sort: Number(item.category_sort ?? 0),
        p_package_size: item.package_size,
        p_stock_unit: item.stock_unit,
        p_minimum_amount: Number(item.minimum_amount ?? 0),
        p_target_amount: Number(item.target_amount ?? 0),
        p_barcode: item.barcode ?? null,
        p_default_cost: null,
        p_cost_currency: "BYN",
        p_variance_recheck_amount: Number(item.variance_recheck_amount ?? 0),
        p_active: item.active !== false,
        p_actor: String(body.employee ?? "").trim() || null,
      });
      if (error) throw error;
      return json({ ok: true, product_key: data });
    }

    if (action === "product_delete") {
      const productKey = String(body.product_key ?? "").trim();
      if (!productKey) throw new Error("product_key required");
      const { data, error } = await db.rpc("stock_catalog_product_delete_v17", {
        p_product_key: productKey,
        p_actor: String(body.employee ?? "").trim() || null,
      });
      if (error) throw error;
      return json({ ok: data === true, deleted: data === true });
    }

    if (action === "category_rename") {
      const oldName = String(body.old_name ?? "").trim();
      const newName = String(body.new_name ?? "").trim();
      if (!oldName || !newName) throw new Error("Укажите старое и новое название категории");
      const { data, error } = await db.rpc("stock_catalog_category_rename_v1", {
        p_old_name: oldName,
        p_new_name: newName,
        p_actor: String(body.employee ?? "").trim() || null,
      });
      if (error) throw error;
      return json({ ok: true, affected: data ?? 0 });
    }

    return json({ error: "UNKNOWN_ACTION" }, 400);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(message);
    return json({ error: message }, 400);
  }
});
