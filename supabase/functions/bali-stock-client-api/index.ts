import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(url, serviceKey, { auth: { persistSession: false } });
const upstream = `${url}/functions/v1/bali-stock-api`;
const CLIENT_KEY = "sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});

function requireClient(req: Request) {
  const key = (req.headers.get("apikey") ?? "").trim();
  if (!key) throw new Error("CLIENT_KEY_REQUIRED");
  if (key !== CLIENT_KEY) throw new Error("CLIENT_KEY_INVALID");
}

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) throw error;
  return data;
}

async function snapshot(req: Request) {
  const headers: Record<string, string> = { Accept: "application/json" };
  const key = req.headers.get("apikey");
  if (key) headers.apikey = key;
  const response = await fetch(`${upstream}?action=snapshot`, { headers, cache: "no-store" });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error ?? `snapshot ${response.status}`);
  return data;
}

async function updateProductMeta(body: any) {
  if (Object.hasOwn(body ?? {}, "default_cost") || Object.hasOwn(body ?? {}, "cost_currency")) {
    throw new Error("purchase price is delivery-only");
  }
  const key = String(body.product_key ?? "");
  if (!key) throw new Error("product_key required");
  const { data: before, error: beforeError } = await db.from("stock_products").select("*").eq("product_key", key).single();
  if (beforeError) throw beforeError;
  const allowed = [
    "target_amount",
    "barcode",
    "variance_recheck_amount",
    "minimum_amount",
    "sell_by_bottle",
    "bottle_sale_price",
    "portion_sale",
    "portion_prices",
    "image_path",
  ];
  const updates: any = { updated_at: new Date().toISOString() };
  for (const field of allowed) if (Object.hasOwn(body, field)) updates[field] = body[field];
  if (Object.hasOwn(updates, "portion_prices")) {
    if (!Array.isArray(updates.portion_prices)) throw new Error("portion_prices must be array");
    updates.portion_prices = updates.portion_prices.map((x: any) => ({
      ml: Math.max(1, Number(x.ml || 0)),
      price: Math.max(0, Number(x.price || 0)),
    }));
  }
  const { data: after, error } = await db.from("stock_products").update(updates).eq("product_key", key).select().single();
  if (error) throw error;
  const { error: auditError } = await db.from("stock_catalog_audit").insert({
    action: "product_meta",
    product_key: key,
    actor: body.employee ?? null,
    before_data: before,
    after_data: after,
  });
  if (auditError) throw auditError;
  return after;
}

function decodeBase64(value: string) {
  const clean = value.includes(",") ? value.slice(value.indexOf(",") + 1) : value;
  const binary = atob(clean);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, "0")).join("");
}

function safeName(value: string) {
  return value.replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 120) || "file";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    requireClient(req);
    const u = new URL(req.url);
    const body: any = req.method === "GET" ? {} : await req.json().catch(() => ({}));
    const action = body.action ?? u.searchParams.get("action") ?? "snapshot";

    if (action === "snapshot") return json(await snapshot(req));
    if (action === "version" || action === "purchase_suggestions" || action === "analytics") {
      const query = new URLSearchParams(u.searchParams);
      query.set("action", action);
      if (body.days != null) query.set("days", String(body.days));
      const headers: Record<string, string> = {
        Accept: "application/json",
        apikey: req.headers.get("apikey")!,
      };
      const response = await fetch(`${upstream}?${query.toString()}`, { headers, cache: "no-store" });
      return new Response(response.body, {
        status: response.status,
        headers: {
          ...cors,
          "Content-Type": response.headers.get("content-type") ?? "application/json",
          "Cache-Control": "no-store",
        },
      });
    }
    if (action === "authorize") return json({ ok: true });

    let result: any = null;
    if (action === "bootstrap") {
      result = await rpc("stock_sync_catalog", { p_items: body.items ?? [] });
    } else if (action === "delivery") {
      result = await rpc("stock_apply_delivery_v2", {
        p_employee: body.employee ?? "",
        p_lines: body.lines ?? [],
        p_supplier: body.supplier_id ?? null,
        p_document_number: body.document_number ?? null,
        p_comment: body.comment ?? null,
        p_attachment_url: body.attachment_url ?? null,
        p_location: body.location_id ?? null,
        p_metadata: body.metadata ?? {},
      });
      const scanId = body?.metadata?.invoice_scan_id;
      if (scanId) {
        const { error: scanUpdateError } = await db.from("stock_invoice_scans").update({
          status: "applied",
          operation_id: result,
          updated_at: new Date().toISOString(),
        }).eq("id", scanId).select("id").maybeSingle();
        if (scanUpdateError) console.error(`invoice scan ${scanId} status update failed: ${scanUpdateError.message}`);
      }
    } else if (action === "writeoff") {
      result = await rpc("stock_apply_writeoff", {
        p_employee: body.employee ?? "",
        p_reason: body.reason ?? "",
        p_lines: body.lines ?? [],
        p_location: body.location_id ?? null,
        p_comment: body.comment ?? null,
      });
    } else if (action === "transfer") {
      result = await rpc("stock_apply_transfer", {
        p_employee: body.employee ?? "",
        p_source: body.source_location_id,
        p_target: body.target_location_id,
        p_lines: body.lines ?? [],
        p_comment: body.comment ?? null,
      });
    } else if (action === "correction") {
      result = await rpc("stock_apply_correction", {
        p_employee: body.employee ?? "",
        p_correction_of: body.correction_of,
        p_reason: body.reason ?? "",
        p_lines: body.lines ?? [],
        p_location: body.location_id ?? null,
      });
    } else if (action === "spot_stocktake") {
      result = await rpc("stock_apply_spot_stocktake", {
        p_employee: body.employee ?? "",
        p_product_key: body.product_key,
        p_quantity: body.quantity_base,
        p_reason: body.reason ?? "",
        p_comment: body.comment ?? null,
        p_device: body.device ?? null,
        p_location: body.location_id ?? null,
        p_metadata: body.metadata ?? {},
      });
    } else if (action === "stocktake") {
      result = await rpc("stock_apply_stocktake_v2", {
        p_employee: body.employee ?? "",
        p_started_at: body.started_at,
        p_active_seconds: body.active_seconds ?? 0,
        p_lines: body.lines ?? [],
        p_metadata: body.metadata ?? {},
      });
    } else if (action === "supplier_upsert") {
      result = await rpc("stock_upsert_supplier", {
        p_id: body.id ?? null,
        p_name: body.name ?? "",
        p_contact: body.contact_person ?? null,
        p_phone: body.phone ?? null,
        p_email: body.email ?? null,
        p_notes: body.notes ?? null,
      });
    } else if (action === "supplier_link") {
      result = await rpc("stock_link_product_supplier", {
        p_product_key: body.product_key,
        p_supplier: body.supplier_id,
        p_sku: body.supplier_sku ?? null,
        p_price: null,
        p_currency: "BYN",
        p_primary: body.is_primary === true,
      });
    } else if (action === "location_upsert") {
      result = await rpc("stock_upsert_location", {
        p_id: body.id ?? null,
        p_name: body.name ?? "",
        p_primary: body.is_primary === true,
      });
    } else if (action === "catalog_product_batch") {
      const items = Array.isArray(body.items)
        ? body.items.map((x: any) => {
            const y = { ...x };
            delete y.default_cost;
            delete y.cost_currency;
            return y;
          })
        : [];
      result = await rpc("stock_catalog_products_batch_v14", {
        p_items: items,
        p_actor: body.employee ?? null,
      });
    } else if (action === "product_meta") {
      await updateProductMeta(body);
      await rpc("stock_bump_version", {});
    } else if (action === "product_meta_batch") {
      const items = Array.isArray(body.items) ? body.items : [];
      for (const item of items) await updateProductMeta({ ...item, employee: body.employee ?? item.employee ?? null });
      await rpc("stock_bump_version", {});
    } else if (action === "product_image_upload") {
      const key = String(body.product_key ?? "");
      if (!key) throw new Error("product_key required");
      const bytes = decodeBase64(String(body.data_base64 ?? ""));
      if (!bytes.length || bytes.length > 5242880) throw new Error("product image must be between 1 byte and 5 MB");
      const mime = String(body.mime_type ?? "image/jpeg");
      const extension = mime.includes("png")
        ? "png"
        : mime.includes("webp")
          ? "webp"
          : mime.includes("heic")
            ? "heic"
            : mime.includes("heif")
              ? "heif"
              : "jpg";
      const keyHash = await sha256(key);
      const path = `${keyHash.slice(0, 16)}/${Date.now()}_${safeName(String(body.file_name ?? `product.${extension}`))}`;
      const { error } = await db.storage.from("stock-product-images").upload(path, bytes, {
        contentType: mime,
        upsert: false,
        cacheControl: "86400",
      });
      if (error) throw error;
      await updateProductMeta({ product_key: key, employee: body.employee ?? null, image_path: path });
      await rpc("stock_bump_version", {});
      result = path;
    } else if (action === "invoice_attachment_upload") {
      const bytes = decodeBase64(String(body.data_base64 ?? ""));
      if (!bytes.length || bytes.length > 15728640) throw new Error("invoice attachment must be between 1 byte and 15 MB");
      const mime = String(body.mime_type ?? "image/jpeg");
      const extension = mime === "application/pdf"
        ? "pdf"
        : mime.includes("png")
          ? "png"
          : mime.includes("webp")
            ? "webp"
            : "jpg";
      const path = `${new Date().toISOString().slice(0, 10)}/${crypto.randomUUID()}_${safeName(String(body.file_name ?? `invoice.${extension}`))}`;
      const { error } = await db.storage.from("stock-invoices").upload(path, bytes, {
        contentType: mime,
        upsert: false,
        cacheControl: "3600",
      });
      if (error) throw error;
      return json({ ok: true, path });
    } else if (action === "invoice_attachment_url") {
      const path = String(body.path ?? "");
      if (!path) throw new Error("attachment path required");
      const { data, error } = await db.storage.from("stock-invoices").createSignedUrl(path, 600);
      if (error) throw error;
      return json({ ok: true, url: data.signedUrl });
    } else if (action === "invoice_scan_save") {
      const { data: scan, error } = await db.from("stock_invoice_scans").insert({
        supplier_id: body.supplier_id ?? null,
        employee_name: body.employee ?? null,
        document_number: body.document_number ?? null,
        attachment_url: body.attachment_url ?? null,
        raw_text: body.raw_text ?? null,
        status: body.status ?? "draft",
      }).select("id").single();
      if (error) throw error;
      const scanLines = (body.lines ?? []).map((x: any) => ({
        scan_id: scan.id,
        source_text: x.source_text ?? "",
        product_key: x.product_key ?? null,
        recognized_quantity: x.recognized_quantity ?? null,
        recognized_packages: x.recognized_packages ?? null,
        unit_cost: x.unit_cost ?? null,
        confidence: x.confidence ?? null,
        manually_corrected: x.manually_corrected === true,
        metadata: x.metadata ?? {},
      }));
      if (scanLines.length) {
        const { error: lineError } = await db.from("stock_invoice_scan_lines").insert(scanLines);
        if (lineError) throw lineError;
      }
      return json({ ok: true, id: scan.id });
    } else if (action === "purchase_request_create") {
      result = await rpc("stock_create_purchase_request", {
        p_supplier: body.supplier_id ?? null,
        p_employee: body.employee ?? "",
        p_lines: body.lines ?? [],
        p_comment: body.comment ?? null,
      });
    } else if (action === "purchase_request_status") {
      await rpc("stock_set_purchase_request_status", {
        p_id: body.id,
        p_status: body.status,
        p_employee: body.employee ?? null,
      });
    } else if (action === "draft_sync") {
      await rpc("stock_sync_draft", {
        p_employee: body.employee ?? "",
        p_status: body.status ?? "draft",
        p_started_at: body.started_at,
        p_active_seconds: body.active_seconds ?? 0,
        p_filled_count: body.filled_count ?? 0,
        p_total_count: body.total_count ?? 0,
        p_payload: body.payload ?? {},
      });
      return json({ ok: true, snapshot: await snapshot(req) });
    } else if (action === "draft_delete") {
      const employee = String(body.employee ?? "").trim();
      if (!employee) throw new Error("employee required");
      const employeeKey = employee.toLowerCase();
      let deletion = db
        .from("stock_draft_mirrors")
        .delete()
        .eq("employee_key", employeeKey);
      const startedAt = String(body.started_at ?? "").trim();
      if (startedAt) deletion = deletion.eq("started_at", startedAt);
      const { data: deletedRows, error: deleteError } = await deletion
        .select("employee_key,started_at");
      if (deleteError) throw deleteError;
      if ((deletedRows ?? []).length) await rpc("stock_bump_version", {});
      const out = await snapshot(req);
      return json({
        ok: true,
        deleted: (deletedRows ?? []).length > 0,
        deleted_count: (deletedRows ?? []).length,
        snapshot: out,
      });
    } else {
      return json({ error: "UNKNOWN_ACTION" }, 400);
    }

    const out = await snapshot(req);
    return json({
      ok: true,
      id: typeof result === "string" ? result : undefined,
      operation_id: action.includes("stocktake") || ["delivery", "writeoff", "transfer", "correction"].includes(action)
        ? result
        : undefined,
      count: action === "bootstrap" ? result : undefined,
      results: action === "catalog_product_batch" ? result : undefined,
      snapshot: out,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    const unauthorized = message === "CLIENT_KEY_REQUIRED" || message === "CLIENT_KEY_INVALID";
    return json({ error: message }, unauthorized ? 401 : 400);
  }
});
