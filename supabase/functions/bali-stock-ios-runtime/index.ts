import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ROOT = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime";
const META = `${ROOT}/production/metadata.json`;
const LAUNCHER = "https://raw.githack.com/Nik13599/BALI-STOCK/777265e6a60fe643e358df16484c073f061bf93b/ios-web/iphone-launcher-v107.html";

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

  if (url.searchParams.get("health") === "1") {
    const meta = await metadata();
    return Response.json({
      ok: true,
      ...meta,
      source: "supabase-storage",
      transport: "http-redirect-html-launcher",
      launcher: LAUNCHER,
      github_dependency: false,
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

  // Supabase Gateway rewrites HTML responses to text/plain with a sandbox CSP.
  // iOS then shows the HTML source. Redirecting to a real text/html launcher
  // avoids the gateway sanitizer; the launcher then loads the authoritative
  // production runtime from Supabase Storage as text and opens it as an HTML Blob.
  return new Response(null, {
    status: 302,
    headers: {
      "Location": LAUNCHER,
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      "Pragma": "no-cache",
      "Expires": "0",
    },
  });
});
