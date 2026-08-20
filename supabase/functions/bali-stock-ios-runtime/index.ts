import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ROOT = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime";
const SOURCE = `${ROOT}/production/bali-stock.html`;
const META = `${ROOT}/production/metadata.json`;
const headers = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  "Pragma": "no-cache",
  "Expires": "0",
  "Access-Control-Allow-Origin": "*",
  "X-Content-Type-Options": "nosniff",
};

async function metadata() {
  try {
    const r = await fetch(`${META}?v=${Date.now()}`, { cache: "no-store" });
    if (!r.ok) throw new Error(String(r.status));
    const value = await r.json();
    return {
      version: String(value?.version ?? "1.0.6"),
      build: Number(value?.build ?? 106),
      sha256: String(value?.sha256 ?? ""),
    };
  } catch (_) {
    return { version: "1.0.6", build: 106, sha256: "" };
  }
}

Deno.serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    if (url.searchParams.get("health") === "1") {
      const meta = await metadata();
      return Response.json({ ok: true, ...meta, source: "supabase-storage", github_dependency: false }, { headers: { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" } });
    }

    const response = await fetch(`${SOURCE}?v=${Date.now()}`, {
      cache: "no-store",
      headers: { Accept: "text/html,*/*" },
    });

    if (!response.ok) throw new Error(`runtime storage HTTP ${response.status}`);

    const html = await response.text();

    if (!/^\s*<!doctype html>/i.test(html)) throw new Error("Invalid HTML response");
    if (!html.includes("BALI STOCK")) throw new Error("BALI STOCK marker missing");

    return new Response(html, { status: 200, headers });
  } catch (error) {
    return new Response(`<!doctype html><html><head><meta charset="utf-8"><title>BALI STOCK</title></head><body><h1>BALI STOCK</h1><p>Runtime loading error</p></body></html>`, { status: 503, headers });
  }
});
