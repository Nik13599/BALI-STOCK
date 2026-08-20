import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(url, serviceKey, { auth: { persistSession: false } });
const CLIENT_API = `${url}/functions/v1/bali-stock-client-api`;
const CLIENT_KEY = "sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29";

function hasValidClientKey(req: Request) {
  return (req.headers.get("apikey") ?? "").trim() === CLIENT_KEY;
}
function publicProductImageUrl(path: string | null | undefined) {
  if (!path) return null;
  const { data } = db.storage.from("stock-product-images").getPublicUrl(path);
  return data.publicUrl;
}

async function snapshot() {
  const [
    { data: products, error: pErr },
    { data: ops, error: oErr },
    { data: lines, error: lErr },
    { data: drafts, error: dErr },
    { data: sync, error: sErr },
    { data: suppliers, error: supErr },
    { data: links, error: linkErr },
    { data: locations, error: locErr },
    { data: locBalances, error: lbErr },
    { data: suggestions, error: sugErr },
    { data: analytics, error: anErr },
    { data: requests, error: reqErr },
    { data: requestLines, error: reqLineErr },
    { data: catalogAudit, error: auditErr },
  ] = await Promise.all([
    db.from("stock_products")
      .select("product_key,name,category_name,category_sort,package_size,stock_unit,minimum_amount,target_amount,barcode,default_cost,cost_currency,variance_recheck_amount,sell_by_bottle,bottle_sale_price,portion_sale,portion_prices,image_path,active,stock_balances(quantity_base,initialized,updated_at)")
      .order("category_sort").order("category_name").order("name"),
    db.from("stock_operations")
      .select("id,operation_type,employee_name,started_at,completed_at,active_seconds,total_seconds,created_at,supplier_id,document_number,comment,attachment_url,source_location_id,target_location_id,correction_of,total_value,metadata")
      .order("created_at", { ascending: false }).limit(1000),
    db.from("stock_operation_lines")
      .select("operation_id,product_key,product_name,category_name,package_size,stock_unit,before_quantity,before_initialized,change_quantity,after_quantity,id,unit_cost,line_value,comment,source_location_id,target_location_id,metadata")
      .order("id"),
    db.from("stock_draft_mirrors")
      .select("employee_name,status,started_at,updated_at,active_seconds,filled_count,total_count,payload")
      .order("updated_at", { ascending: false }),
    db.from("stock_sync_state").select("version,updated_at").eq("singleton", true).single(),
    db.from("stock_suppliers").select("id,name,contact_person,phone,email,notes,active,created_at,updated_at").order("name"),
    db.from("stock_product_suppliers").select("product_key,supplier_id,supplier_sku,last_price,currency,is_primary,active,updated_at"),
    db.from("stock_locations").select("id,name,is_primary,active,sort_order,created_at,updated_at").order("sort_order").order("name"),
    db.from("stock_location_balances").select("location_id,product_key,quantity_base,initialized,updated_at"),
    db.rpc("stock_purchase_suggestions"),
    db.rpc("stock_analytics_summary", { p_days: 30 }),
    db.from("stock_purchase_requests").select("id,supplier_id,status,created_by,comment,created_at,updated_at").order("created_at", { ascending: false }).limit(100),
    db.from("stock_purchase_request_lines").select("id,request_id,product_key,suggested_quantity,requested_quantity,unit_cost,comment").order("id"),
    db.from("stock_catalog_audit").select("id,action,product_key,actor,before_data,after_data,created_at").order("created_at", { ascending: false }).limit(500),
  ]);

  const error = pErr || oErr || lErr || dErr || sErr || supErr || linkErr || locErr || lbErr || sugErr || anErr || reqErr || reqLineErr || auditErr;
  if (error) throw error;

  const byOperation = new Map<string, any[]>();
  for (const line of lines ?? []) {
    const rows = byOperation.get(line.operation_id) ?? [];
    rows.push(line);
    byOperation.set(line.operation_id, rows);
  }
  const byRequest = new Map<string, any[]>();
  for (const line of requestLines ?? []) {
    const rows = byRequest.get(line.request_id) ?? [];
    rows.push(line);
    byRequest.set(line.request_id, rows);
  }

  return {
    version: sync?.version ?? 0,
    updated_at: sync?.updated_at,
    products: (products ?? []).map((product: any) => ({
      ...product,
      image_url: publicProductImageUrl(product.image_path),
      balance: Array.isArray(product.stock_balances) ? product.stock_balances[0] ?? null : product.stock_balances ?? null,
    })),
    operations: (ops ?? []).map((operation: any) => ({ ...operation, lines: byOperation.get(operation.id) ?? [] })),
    drafts: drafts ?? [],
    suppliers: suppliers ?? [],
    product_suppliers: links ?? [],
    locations: locations ?? [],
    location_balances: locBalances ?? [],
    purchase_suggestions: suggestions ?? [],
    analytics: analytics ?? {},
    purchase_requests: (requests ?? []).map((request: any) => ({ ...request, lines: byRequest.get(request.id) ?? [] })),
    catalog_audit: catalogAudit ?? [],
  };
}

async function forwardToClientApi(body: any) {
  const response = await fetch(CLIENT_API, {
    method: "POST",
    headers: {
      apikey: CLIENT_KEY,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return new Response(response.body, {
    status: response.status,
    headers: {
      ...cors,
      "Content-Type": response.headers.get("content-type") ?? "application/json",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!hasValidClientKey(req)) return json({ error: "CLIENT_KEY_REQUIRED" }, 401);
  try {
    const u = new URL(req.url);
    const body: any = req.method === "GET" ? {} : await req.json().catch(() => ({}));
    const action = String(body.action ?? u.searchParams.get("action") ?? "snapshot");

    if (action === "snapshot") return json(await snapshot());
    if (action === "version") {
      const { data, error } = await db.from("stock_sync_state").select("version,updated_at").eq("singleton", true).single();
      if (error) throw error;
      return json(data);
    }
    if (action === "purchase_suggestions") {
      const { data, error } = await db.rpc("stock_purchase_suggestions");
      if (error) throw error;
      return json({ items: data ?? [] });
    }
    if (action === "analytics") {
      const days = Number(body.days ?? u.searchParams.get("days") ?? 30);
      const { data, error } = await db.rpc("stock_analytics_summary", { p_days: days });
      if (error) throw error;
      return json(data ?? {});
    }

    return forwardToClientApi({ ...body, action });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    return json({ error: message }, 400);
  }
});
