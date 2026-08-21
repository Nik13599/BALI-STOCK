import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ROOT = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime";
const META = `${ROOT}/production/metadata.json`;
const WEB_APP = "https://nik13599.github.io/BALI-STOCK/";
const LEGACY_LAUNCHER = "https://raw.githack.com/Nik13599/BALI-STOCK/777265e6a60fe643e358df16484c073f061bf93b/ios-web/iphone-launcher-v107.html";
const TARGET_TTL_MS = 60_000;

type LaunchTarget = {
  url: string;
  cameraSafe: boolean;
  source: "github-pages" | "supabase-storage";
};

let cachedTarget: { expiresAt: number; value: LaunchTarget } | null = null;

async function launchTarget(force = false): Promise<LaunchTarget> {
  if (!force && cachedTarget && cachedTarget.expiresAt > Date.now()) {
    return cachedTarget.value;
  }

  let value: LaunchTarget = {
    url: LEGACY_LAUNCHER,
    cameraSafe: false,
    source: "supabase-storage",
  };
  try {
    const response = await fetch(`${WEB_APP}?edge_probe=${Date.now()}`, {
      cache: "no-store",
      headers: { Accept: "text/html" },
    });
    const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
    const html = await response.text();
    const valid = response.ok &&
      contentType.startsWith("text/html") &&
      html.trimStart().toLowerCase().startsWith("<!doctype html>") &&
      html.includes("__BALI_STOCK_IOS_SCANNER_COMPAT__") &&
      html.includes("__BALI_STOCK_VISUAL_CONTRACT__") &&
      html.includes("bali-html5-qrcode-v238") &&
      !html.includes("blob:");
    if (valid) {
      value = { url: WEB_APP, cameraSafe: true, source: "github-pages" };
    }
  } catch (_) {
    // Preserve the current production UI if the verified camera host is unavailable.
  }
  cachedTarget = { expiresAt: Date.now() + TARGET_TTL_MS, value };
  return value;
}

async function metadata() {
  try {
    const r = await fetch(`${META}?v=${Date.now()}`, { cache: "no-store" });
    if (!r.ok) throw new Error(String(r.status));
    const value = await r.json();
    return {
      version: String(value?.version ?? "1.0.4"),
      build: Number(value?.build ?? 104),
      sha256: String(value?.sha256 ?? ""),
    };
  } catch (_) {
    return { version: "1.0.4", build: 104, sha256: "" };
  }
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const target = await launchTarget(url.searchParams.get("refresh") === "1");

  if (url.searchParams.get("health") === "1") {
    const meta = await metadata();
    return Response.json({
      ok: true,
      ...meta,
      source: target.source,
      transport: target.cameraSafe ? "verified-https-document" : "legacy-html-launcher",
      web_app: WEB_APP,
      github_dependency: true,
      active_target: target.url,
      camera_safe_origin: target.cameraSafe,
      blob_launcher: !target.cameraSafe,
      interface_guard: true,
      password_prompt: false,
      scanner_workflows: true,
      invoice_auto: true,
      compact_product_card: true,
      purchase_requests: true,
      catalog_edit: true,
    }, {
      headers: {
        "Cache-Control": "no-store",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }

  // Never switch users to an outdated Pages build: the verified document must
  // contain both the scanner and frozen visual-contract markers. Until then,
  // preserve the exact 1.0.5 production interface through the legacy launcher.
  return new Response(null, {
    status: 302,
    headers: {
      "Location": target.url,
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      "Pragma": "no-cache",
      "Expires": "0",
    },
  });
});
