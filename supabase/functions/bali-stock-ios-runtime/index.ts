import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SOURCE = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime/production/bali-stock.html";
const headers = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  "Pragma": "no-cache",
  "Expires": "0",
  "Access-Control-Allow-Origin": "*",
  "X-Content-Type-Options": "nosniff",
};

Deno.serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    if (url.searchParams.get("health") === "1") {
      return Response.json({
        ok: true,
        version: "1.0.1",
        source: "supabase-storage",
        github_dependency: false,
        password_prompt: false,
        scanner_workflows: true,
        invoice_auto: true,
        compact_product_card: true,
        purchase_requests: true,
        catalog_edit: true,
      }, { headers: { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" } });
    }

    const response = await fetch(`${SOURCE}?v=${Date.now()}`, {
      cache: "no-store",
      headers: { Accept: "text/plain,*/*" },
    });
    if (!response.ok) throw new Error(`runtime storage HTTP ${response.status}`);
    const html = await response.text();
    if (!/^\s*<!doctype html>/i.test(html) || !html.includes("BALI STOCK")) throw new Error("runtime storage returned invalid HTML");
    if (html.includes("raw.githack.com") || html.includes("raw.githubusercontent.com/Nik13599/BALI-STOCK")) throw new Error("GitHub dependency detected");
    if (html.includes("Введите пароль доступа")) throw new Error("password prompt detected");
    if (!html.includes("__BALI_STOCK_SUPABASE_RUNTIME__")) throw new Error("runtime marker missing");
    return new Response(html, { status: 200, headers });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const safe = message.replaceAll("<", "&lt;").replaceAll(">", "&gt;");
    return new Response(
      `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#07110c"><title>BALI STOCK</title></head><body style="margin:0;background:#07110c;color:#fff;font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:24px"><h1 style="color:#39ff6a">BALI STOCK</h1><p>Не удалось загрузить рабочую версию приложения.</p><p style="color:#ff8d94">${safe}</p><button onclick="location.reload()" style="padding:12px 16px;border:0;border-radius:12px;background:#39ff6a;font-weight:800">Повторить</button></body></html>`,
      { status: 503, headers },
    );
  }
});
