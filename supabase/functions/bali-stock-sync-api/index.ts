import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
const upstream = `${supabaseUrl}/functions/v1/bali-stock-client-api`;
const CLIENT_KEY = "sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29";

function decodeBase64(value: string) {
  const clean = value.includes(",") ? value.slice(value.indexOf(",") + 1) : value;
  const binary = atob(clean);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}
function safeName(value: string) {
  return value.replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 120) || "invoice";
}
function hasValidClientKey(req: Request) {
  return (req.headers.get("apikey") ?? "").trim() === CLIENT_KEY;
}
async function currentSnapshot() {
  const r = await fetch(`${upstream}?action=snapshot`, {
    headers: { apikey: CLIENT_KEY, Accept: "application/json" },
    cache: "no-store",
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d?.error ?? `snapshot HTTP ${r.status}`);
  return d;
}
async function forward(body: any) {
  const response = await fetch(upstream, {
    method: "POST",
    headers: {
      apikey: CLIENT_KEY,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!hasValidClientKey(req)) return json({ error: "CLIENT_KEY_REQUIRED" }, 401);
  if (req.method !== "POST") return json({ error: "POST_REQUIRED" }, 405);

  let actionId = "";
  let reserved = false;
  let upstreamApplied = false;
  try {
    const body = await req.json().catch(() => ({}));
    actionId = String(body.client_action_id ?? "").trim();
    const action = String(body.action ?? "").trim();
    if (!actionId || !action) return json({ error: "client_action_id and action are required" }, 400);

    const { error: reserveError } = await db.from("stock_client_actions").insert({
      action_id: actionId,
      action_type: action,
      status: "pending",
    });

    if (reserveError) {
      const { data: existing, error } = await db.from("stock_client_actions")
        .select("action_id,action_type,status,result_id,created_at,completed_at")
        .eq("action_id", actionId)
        .maybeSingle();
      if (error) throw error;
      if (existing?.status === "completed") {
        return json({ ok: true, duplicate: true, operation_id: existing.result_id, snapshot: await currentSnapshot() });
      }
      return json({ error: "Операция уже синхронизируется. Повторите позже.", pending: true }, 409);
    }
    reserved = true;

    // Password/PIN authentication is intentionally not used. The app channel
    // is authenticated by the same BALI STOCK publishable client key as client-api.
    const auth = await forward({ action: "authorize" });
    if (!auth.response.ok) {
      await db.from("stock_client_actions").delete().eq("action_id", actionId);
      reserved = false;
      return json(auth.data, auth.response.status);
    }

    let response: Response;
    let data: any;

    if (action === "delivery_bundle") {
      const delivery = { ...(body.delivery ?? {}), action: "delivery" };
      let attachmentPath: string | null = null;

      if (body.attachment?.data_base64) {
        const bytes = decodeBase64(String(body.attachment.data_base64));
        if (!bytes.length || bytes.length > 15728640) throw new Error("invoice attachment must be between 1 byte and 15 MB");
        const mime = String(body.attachment.mime_type ?? "image/jpeg");
        const fileName = safeName(String(body.attachment.file_name ?? "invoice.jpg"));
        attachmentPath = `offline/${actionId}_${fileName}`;
        const { error } = await db.storage.from("stock-invoices").upload(attachmentPath, bytes, {
          contentType: mime,
          upsert: true,
          cacheControl: "3600",
        });
        if (error) throw error;
        delivery.attachment_url = attachmentPath;
      }

      let scanId: string | null = null;
      const scanBody = body.scan;
      if (scanBody?.raw_text) {
        const { data: scan, error } = await db.from("stock_invoice_scans").insert({
          supplier_id: scanBody.supplier_id ?? delivery.supplier_id ?? null,
          employee_name: scanBody.employee ?? delivery.employee ?? null,
          document_number: scanBody.document_number ?? delivery.document_number ?? null,
          attachment_url: attachmentPath,
          raw_text: scanBody.raw_text,
          status: "reviewed",
        }).select("id").single();
        if (error) throw error;
        scanId = String(scan.id);
        const scanLines = (scanBody.lines ?? []).map((x: any) => ({
          scan_id: scan.id,
          source_text: x.source_text ?? "",
          product_key: x.product_key ?? null,
          recognized_quantity: x.recognized_quantity ?? null,
          recognized_packages: x.recognized_packages ?? null,
          unit_cost: x.unit_cost ?? null,
          confidence: x.confidence ?? null,
          manually_corrected: x.manually_corrected == true,
          metadata: x.metadata ?? {},
        }));
        if (scanLines.length) {
          const { error: lineError } = await db.from("stock_invoice_scan_lines").insert(scanLines);
          if (lineError) throw lineError;
        }
      }

      delivery.metadata = {
        ...(delivery.metadata ?? {}),
        ...(scanId ? { invoice_scan_id: scanId } : {}),
        ocr_used: Boolean(scanBody?.raw_text),
        invoice_archived: Boolean(attachmentPath),
      };
      const result = await forward(delivery);
      response = result.response;
      data = result.data;
    } else {
      const forwardBody = { ...body };
      delete forwardBody.client_action_id;
      const result = await forward(forwardBody);
      response = result.response;
      data = result.data;
    }

    if (!response.ok) {
      await db.from("stock_client_actions").delete().eq("action_id", actionId);
      reserved = false;
      return json(data, response.status);
    }

    upstreamApplied = true;
    const { error: completeError } = await db.from("stock_client_actions").update({
      status: "completed",
      result_id: data?.operation_id == null ? null : String(data.operation_id),
      completed_at: new Date().toISOString(),
    }).eq("action_id", actionId);
    if (completeError) throw completeError;

    return json(data, response.status);
  } catch (error) {
    if (actionId && reserved && !upstreamApplied) {
      await db.from("stock_client_actions").delete().eq("action_id", actionId).catch(() => {});
    }
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    return json({ error: message, pending: upstreamApplied }, upstreamApplied ? 409 : 400);
  }
});
