import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const UPSTREAM = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-ios";

const headers = {
  "Content-Type": "text/plain; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  "Pragma": "no-cache",
  "Expires": "0",
  "Access-Control-Allow-Origin": "*",
};

function icon(path: string) {
  return `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;
}

const icons = {
  home: icon('<path d="M3 11 12 3.5 21 11M5.5 9.5V20h13V9.5M9.3 20v-6h5.4v6"/>'),
  stock: icon('<rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M4.5 10h15M4.5 15h15M9 5v4M14.8 11v3"/>'),
  stocktake: icon('<rect x="5" y="4.5" width="14" height="16" rx="2"/><path d="M9 3.5h6M9 7.5h6M8 13l2.5 2.5 6-5.5"/>'),
  purchases: icon('<path d="M3 5h2.5l1.7 10.2h10.3L20 8H6M9 19h.1M17 19h.1"/>'),
  delivery: icon('<rect x="4" y="9" width="16" height="11" rx="2"/><path d="M12 3v11M8.5 10.5 12 14l3.5-3.5M4.5 9 8 6.5M19.5 9 16 6.5"/>'),
  settings: icon('<circle cx="12" cy="12" r="3.2"/><circle cx="12" cy="12" r="7.2"/><path d="M12 2v2.4M12 19.6V22M2 12h2.4M19.6 12H22M4.9 4.9l1.7 1.7M17.4 17.4l1.7 1.7M19.1 4.9l-1.7 1.7M6.6 17.4l-1.7 1.7"/>'),
};

function patchHtml(source: string) {
  let html = source;

  // Safari cannot parse the legacy pattern `if (...) return,p=...`.
  // Convert every occurrence before any script is allowed to execute.
  html = html.replace(/return,([A-Za-z_$][A-Za-z0-9_$]*)=/g, "return;let $1=");
  html = html.replace("(!p.stock_unit==='pcs'&&e>=p.package_size)", "(p.stock_unit!=='pcs'&&e>=p.package_size)");
  html = html.replaceAll('>📷 Сканировать</button>', '>📷 Сканировать код</button>');
  html = html.replaceAll('<h2>Контроль</h2>', '<h2>Настройки</h2>');

  const newNav = `nav.innerHTML='<button data-tab="home" class="active"><b>${icons.home}</b>Главная</button><button data-tab="stock"><b>${icons.stock}</b>Склад</button><button data-tab="count"><b>${icons.stocktake}</b>Переучёт</button><button data-tab="buy"><b>${icons.purchases}</b>Закупки</button><button data-tab="delivery"><b>${icons.delivery}</b>Поставка</button><button data-tab="control"><b>${icons.settings}</b>Настройки</button>';`;
  html = html.replace(/nav\.innerHTML='<button data-tab="home" class="active">[\s\S]*?<\/button>';/, newNav);

  const navCss = `<style id="bali-v14-runtime-nav">.tabs b{display:grid!important;place-items:center;height:22px;margin-bottom:2px}.tabs b svg{display:block}.tabs button{line-height:1.1}.tabs button.active b{color:#39ff6a}</style>`;
  html = html.replace('</head>', navCss + '\n</head>');

  return html;
}

function audit(html: string) {
  const remainingLegacy = (html.match(/return,[A-Za-z_$][A-Za-z0-9_$]*=/g) || []).length;
  const snapshotPos = html.indexOf('async function snapshot');
  const v14SnapshotPos = html.indexOf('baseSnapshot=snapshot');
  const navMatch = html.match(/nav\.innerHTML='<button data-tab="home" class="active">[\s\S]*?<\/button>';/)?.[0] || '';
  return {
    ok: remainingLegacy === 0 && snapshotPos >= 0 && v14SnapshotPos > snapshotPos && navMatch.includes('Главная') && navMatch.includes('Склад') && navMatch.includes('Переучёт') && navMatch.includes('Закупки') && navMatch.includes('Поставка') && navMatch.includes('Настройки') && !navMatch.includes('data-tab="history"'),
    remaining_legacy_return_comma: remainingLegacy,
    snapshot_found: snapshotPos >= 0,
    snapshot_before_v14: v14SnapshotPos > snapshotPos,
    history_in_runtime_nav: navMatch.includes('data-tab="history"'),
    runtime_nav: navMatch.replace(/<svg[\s\S]*?<\/svg>/g, '[icon]'),
  };
}

Deno.serve(async (req: Request) => {
  try {
    const response = await fetch(`${UPSTREAM}?runtime=3&ts=${Date.now()}`, {
      cache: 'no-store',
      headers: { 'User-Agent': 'BALI-STOCK-iOS-Runtime/3', Accept: 'text/html,*/*' },
    });
    if (!response.ok) throw new Error(`upstream HTTP ${response.status}`);
    const html = patchHtml(await response.text());
    const result = audit(html);

    if (new URL(req.url).searchParams.get('health') === '1') {
      return new Response(JSON.stringify(result), {
        status: result.ok ? 200 : 500,
        headers: { ...headers, 'Content-Type': 'application/json; charset=utf-8' },
      });
    }

    if (!result.ok) throw new Error(`runtime validation failed: ${JSON.stringify(result)}`);
    return new Response(html, { status: 200, headers });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(`BALI STOCK runtime error: ${message}`, { status: 500, headers });
  }
});
