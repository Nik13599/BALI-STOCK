import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ROOT = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime";
const META = `${ROOT}/production/metadata.json`;
const WEB_APP = "https://nik13599.github.io/BALI-STOCK/";

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
      source: "github-pages",
      transport: "https-redirect",
      web_app: WEB_APP,
      github_dependency: true,
      camera_safe_origin: true,
      blob_launcher: false,
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
  // Redirect to the camera-safe HTTPS document used by the current profile.
  // This also keeps previously installed profiles functional without a Blob URL.
  return new Response(null, {
    status: 302,
    headers: {
      "Location": WEB_APP,
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      "Pragma": "no-cache",
      "Expires": "0",
    },
  });
});
