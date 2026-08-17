// BALI STOCK iPhone V13 — complete mobile feature layer.
const V13_VERSION = '13.0.0';
const V13_CATALOG_API = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-catalog-api';

const __v13StockFilter = { query: '', category: '', low: false, uninitialized: false };
const __v13HistoryFilter = { query: '', type: '' };
let __v13WallTimer = null;

function __v13Categories() {
  const map = new Map();
  (S.products || []).filter(p => p.active !== false).forEach(p => {
    const name = String(p.category_name || 'Без категории');
    const sort = Number(p.category_sort || 0);
    if (!map.has(name) || sort < map.get(name)) map.set(name, sort);
  });
  return [...map.entries()].sort((a,b) => a[1] - b[1] || a[0].localeCompare(b[0], 'ru')).map(x => x[0]);
}
function __v13ProductSearchText(p) {
  return [p.name, p.category_name, p.barcode, p.stock_unit, p.package_size].filter(Boolean).join(' ').toLowerCase();
}
function __v13PriceForProduct(p) {
  let price = p.default_cost == null ? null : Number(p.default_cost);
  let currency = p.cost_currency || 'BYN';
  if (price == null || Number.isNaN(price)) {
    const links = (S.product_suppliers || []).filter(x => x.product_key === keyOf(p) && x.active !== false && x.last_price != null);
    const primary = links.find(x => x.is_primary) || links[0];
    if (primary) { price = Number(primary.last_price); currency = primary.currency || 'BYN'; }
  }
  return { price, currency };
}
function __v13StockValue() {
  let total = 0, missing = 0, foreign = 0;
  (S.products || []).filter(p => p.active !== false && init(p)).forEach(p => {
    const pr = __v13PriceForProduct(p);
    if (pr.price == null || Number.isNaN(pr.price)) { missing++; return; }
    if (pr.currency !== 'BYN') { foreign++; return; }
    const packages = p.stock_unit === 'pcs' ? qty(p) : qty(p) / Math.max(1, n(p.package_size));
    total += packages * pr.price;
  });
  return { total, missing, foreign };
}
function __v13FmtValue(v) { return `${Number(v || 0).toFixed(2).replace('.', ',')} BYN`; }
function __v13Css() {
  if (document.getElementById('v13css')) return;
  const s = document.createElement('style'); s.id = 'v13css';
  s.textContent = `
    .v13-filterbar{display:grid;grid-template-columns:minmax(0,1fr) minmax(150px,.55fr);gap:8px;margin:8px 0 10px}
    .v13-chips{display:flex;gap:7px;overflow:auto;padding:2px 0 8px;scrollbar-width:none}.v13-chips::-webkit-scrollbar{display:none}
    .v13-chip{white-space:nowrap;background:#12271a!important;color:#9cffb4!important;border:1px solid #2a6240!important;padding:8px 11px!important;font-size:12px!important}
    .v13-chip.active{background:#39ff6a!important;color:#031408!important}
    .v13-switches{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 12px}.v13-check{background:#101c15;border:1px solid #294233;border-radius:12px;padding:8px 10px;font-size:12px;color:#c9dbcf}
    .v13-check input{margin-right:6px}.v13-hidden{display:none!important}.v13-stack{display:grid;gap:8px}.v13-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:9px}
    .v13-kpi{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px;margin:10px 0}.v13-kpi .metric{min-width:0}
    .v13-delta-pos{color:#ffcb5c}.v13-delta-neg{color:#ff7c85}.v13-scroll{max-height:58vh;overflow:auto}
    .v13-section-title{font-size:18px;font-weight:950;margin:20px 0 8px;color:#39ff6a}.v13-code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:#a7b8ae}
    @media(max-width:620px){.v13-filterbar{grid-template-columns:1fr}.v13-kpi{grid-template-columns:1fr 1fr}}
  `;
  document.head.appendChild(s);
}
__v13Css();

// ---------- Warehouse search, category filter and product code search ----------
renderStock = function() {
  const cats = __v13Categories();
  const active = (S.products || []).filter(p => p.active !== false);
  let html = `<div class="toolbar noPrint"><button id="v12Scan">📷 Сканировать</button><button id="v12ManualCode" class="secondary">⌨️ Код</button><button id="stockPdf" class="secondary">PDF</button></div>`;
  html += `<div class="v13-filterbar noPrint"><input id="stockSearch" class="input" placeholder="Найти товар по названию, QR или штрихкоду" value="${esc(__v13StockFilter.query)}"><select id="v13Category" class="input"><option value="">Все категории</option>${cats.map(c=>`<option value="${esc(c)}" ${__v13StockFilter.category===c?'selected':''}>${esc(c)}</option>`).join('')}</select></div>`;
  html += `<div class="v13-chips noPrint"><button class="v13-chip ${!__v13StockFilter.category?'active':''}" data-cat="">Все</button>${cats.map(c=>`<button class="v13-chip ${__v13StockFilter.category===c?'active':''}" data-cat="${esc(c)}">${esc(c)}</button>`).join('')}</div>`;
  html += `<div class="v13-switches noPrint"><label class="v13-check"><input id="v13Low" type="checkbox" ${__v13StockFilter.low?'checked':''}> Только критический</label><label class="v13-check"><input id="v13Uninit" type="checkbox" ${__v13StockFilter.uninitialized?'checked':''}> Не пересчитано</label></div>`;
  html += `<div class="row noPrint" style="flex-wrap:wrap"><div class="metric"><span class="muted">Позиций</span><b>${active.length}</b></div><div class="metric"><span class="muted">Критический</span><b>${active.filter(p=>init(p)&&qty(p)<=n(p.minimum_amount)).length}</b></div><div class="metric"><span class="muted">Категорий</span><b>${cats.length}</b></div></div>`;
  const groups = groupProducts(active);
  for (const cat of cats) {
    const items = groups[cat] || [];
    html += `<div class="cat v13-stock-cat" data-cat="${esc(cat)}"><span>${esc(cat)}</span><small>${items.length} поз.</small></div><div class="catbody v13-stock-body" data-cat="${esc(cat)}">`;
    for (const p of items) {
      const status = !init(p) ? 'unknown' : qty(p)<=n(p.minimum_amount) ? 'low' : '';
      const code = String(p.barcode || '').trim();
      html += `<div class="card product v13-product" data-category="${esc(cat)}" data-search="${esc(__v13ProductSearchText(p))}" data-low="${init(p)&&qty(p)<=n(p.minimum_amount)?'1':'0'}" data-uninit="${!init(p)?'1':'0'}"><div class="row"><div class="grow"><div class="name">${esc(p.name)}</div><div class="muted">${esc(packSize(p))} • минимум ${n(p.minimum_amount)} ${unit(p)}${n(p.target_amount)>0?` • цель ${n(p.target_amount)} ${unit(p)}`:''}</div><div class="amount ${status}">${!init(p)?'Остаток не введён':esc(parts(qty(p),p))}</div>${code?`<div class="v13-code">Код: ${esc(code)}</div>`:''}</div><button class="secondary noPrint ph" data-key="${esc(keyOf(p))}">История</button></div></div>`;
    }
    html += `</div>`;
  }
  return html;
};
function __v13ApplyStockFilters() {
  const q = __v13StockFilter.query.trim().toLowerCase();
  document.querySelectorAll('.v13-product').forEach(card => {
