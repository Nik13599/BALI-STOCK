(function () {
  'use strict';
  window.__BALI_STOCK_V15_UI__ = '15.0';

  var GREEN = '#39ff6a';
  var state = {
    stockView: localStorage.getItem('bali-v15-stock-view') || 'compact',
    stockSearch: '',
    stockCategory: '',
    purchaseTab: 'needed',
    purchaseSearch: '',
    purchaseSupplier: '',
    purchaseQty: {},
    requests: [],
    requestsLoaded: false,
    requestsLoading: false
  };

  function clean(v) { return String(v == null ? '' : v).trim(); }
  function lower(v) { return clean(v).toLowerCase(); }
  function html(v) { return typeof esc === 'function' ? esc(v) : clean(v).replace(/[&<>"']/g, function (c) { return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]; }); }
  function productKey(p) { return keyOf(p); }
  function packageBase(p) { return p.stock_unit === 'pcs' ? 1 : Math.max(1, Number(p.package_size || 1)); }
  function packageName(p) { return p.stock_unit === 'pcs' ? 'шт.' : p.stock_unit === 'g' ? 'уп.' : 'бут.'; }
  function formatStock(q, p) { return init(p) || Number(q) >= 0 ? parts(Number(q || 0), p) : '—'; }
  function moneySafe(v, c) { return v == null || !Number.isFinite(Number(v)) ? '—' : money(Number(v), c || 'BYN'); }
  function productByKey(k) { return (S.products || []).find(function (p) { return productKey(p) === k; }) || null; }
  function supplierById(id) { return (S.suppliers || []).find(function (s) { return s.id === id && s.active !== false; }) || null; }
  function supplierLinks(p) { var k = productKey(p); return (S.product_suppliers || []).filter(function (x) { return x.active !== false && x.product_key === k; }); }
  function primarySupplierLink(p) {
    var links = supplierLinks(p);
    return links.find(function (x) { return x.is_primary === true; }) || links[0] || null;
  }
  function primarySupplier(p) { var link = primarySupplierLink(p); return link ? supplierById(link.supplier_id) : null; }
  function currentSupplierPrice(p) { var link = primarySupplierLink(p); return link && link.last_price != null ? Number(link.last_price) : (p.default_cost == null ? null : Number(p.default_cost)); }
  function categorySort(a, b) {
    var sa = Number(a.category_sort == null ? 999999 : a.category_sort);
    var sb = Number(b.category_sort == null ? 999999 : b.category_sort);
    if (sa !== sb) return sa - sb;
    var c = String(a.category_name || '').localeCompare(String(b.category_name || ''), 'ru');
    if (c) return c;
    return String(a.name || '').localeCompare(String(b.name || ''), 'ru');
  }
  function statusFor(p) {
    if (!init(p)) return {text:'НЕ ВВЕДЕНО', cls:'neutral'};
    var q = qty(p), min = Number(p.minimum_amount || 0);
    if (q <= 0) return {text:'НЕТ В НАЛИЧИИ', cls:'danger'};
    if (min > 0 && q <= Math.ceil(min / 2)) return {text:'КРИТИЧНО', cls:'danger'};
    if (min > 0 && q <= min) return {text:'МАЛО', cls:'warn'};
    return {text:'НОРМА', cls:'ok'};
  }
  function latestProductOperation(p, types) {
    var key = productKey(p), name = lower(p.name), best = null;
    (S.operations || []).forEach(function (o) {
      if (types && types.indexOf(o.operation_type) < 0) return;
      var hit = (o.lines || []).some(function (l) { return l.product_key === key || lower(l.product_name) === name; });
      if (!hit) return;
      if (!best || new Date(o.created_at) > new Date(best.created_at)) best = o;
    });
    return best;
  }
  function movementLabel(p) {
    var op = latestProductOperation(p, null);
    if (!op) return '—';
    var key = productKey(p), line = (op.lines || []).find(function (l) { return l.product_key === key || lower(l.product_name) === lower(p.name); });
    var names = {delivery:'Поставка',stocktake:'Переучёт',spot_stocktake:'Точечный переучёт',writeoff:'Списание',transfer:'Перемещение',correction:'Корректировка'};
    var delta = line ? Number(line.change_quantity || 0) : 0;
    return (names[op.operation_type] || op.operation_type) + (delta ? ' ' + (delta > 0 ? '+' : '−') + formatStock(Math.abs(delta), p) : '') + ' • ' + dt(op.created_at);
  }

  function ensureCss() {
    if (document.getElementById('baliV15Css')) return;
    var style = document.createElement('style');
    style.id = 'baliV15Css';
    style.textContent = [
      '.v15gear{width:38px;height:38px;padding:7px;border-radius:12px;background:#183522;color:'+GREEN+';display:grid;place-items:center}',
      '.v15gear svg{width:22px;height:22px}',
      '.v15hero{display:grid;grid-template-columns:78px minmax(0,1fr) 40px;gap:11px;align-items:start}',
      '.v15img{width:78px;height:78px;object-fit:contain;background:#fff;border-radius:13px}',
      '.v15placeholder{width:78px;height:78px;border-radius:13px;background:#18281d;display:grid;place-items:center;font-size:27px}',
      '.v15title{font-size:19px;font-weight:1000;line-height:1.06}.v15cat{color:'+GREEN+';font-weight:850;margin-top:3px}',
      '.v15qty{font-size:18px;font-weight:1000;margin-top:7px}.v15status{display:inline-block;margin-top:5px;border:1px solid #456;border-radius:99px;padding:4px 8px;font-size:11px;font-weight:900}',
      '.v15status.ok{color:'+GREEN+';border-color:#39ff6a88}.v15status.warn{color:#ffcb5c}.v15status.danger{color:#ff737c}.v15status.neutral{color:#a8b3ac}',
      '.v15grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:9px}.v15box{background:#101c15;border:1px solid #294233;border-radius:14px;padding:11px}.v15head{font-weight:1000;margin-bottom:6px}',
      '.v15row{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.2fr);gap:8px;padding:3px 0;font-size:12.5px}.v15row span{color:#9fb3a5}.v15row b{text-align:right;overflow-wrap:anywhere}',
      '.v15category{font-size:20px;font-weight:1000;color:'+GREEN+';margin:17px 2px 7px;text-transform:uppercase;display:flex;justify-content:space-between}.v15category small{font-size:11px}',
      '.v15counter{display:flex;align-items:center;gap:5px}.v15counter button{width:38px;height:36px;padding:0}.v15counter b{min-width:62px;text-align:center}',
      '.v15overlay{position:fixed;inset:0;z-index:100;background:rgba(0,0,0,.82);display:grid;place-items:center;padding:22px}.v15overlayBox{background:#101c15;border:1px solid #294233;border-radius:18px;padding:23px;max-width:340px;text-align:center}.v15spinner{width:38px;height:38px;margin:0 auto 13px;border:3px solid #294233;border-top-color:'+GREEN+';border-radius:50%;animation:v15spin .8s linear infinite}@keyframes v15spin{to{transform:rotate(360deg)}}',
      '.v15table{width:100%;border-collapse:collapse;min-width:700px}.v15table th,.v15table td{padding:9px 7px;border-bottom:1px solid #294233;text-align:left;font-size:12px}',
      '@media(max-width:520px){.v15grid{grid-template-columns:1fr}.v15hero{grid-template-columns:72px minmax(0,1fr) 36px}.v15img,.v15placeholder{width:72px;height:72px}.v15row{font-size:12px}}'
    ].join('');
    document.head.appendChild(style);
  }

  function gearSvg() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M8 3.2h8L21 8v8l-5 4.8H8L3 16V8l5-4.8Z"/><circle cx="12" cy="12" r="3.2"/><path d="M12 5.8v2.4M12 15.8v2.4M5.8 12h2.4M15.8 12h2.4"/></svg>';
  }

  var legacyShowProduct = window.v14ShowProduct;
  function invokeLegacy(p, id) {
    closeModal();
    legacyShowProduct(p);
    setTimeout(function () { var button = document.getElementById(id); if (button) button.click(); }, 40);
  }
  function rows(items) { return items.map(function (x) { return '<div class="v15row"><span>'+html(x[0])+'</span><b>'+html(x[1])+'</b></div>'; }).join(''); }

  function openProductSettings(p) {
    var supplier = primarySupplier(p);
    openModal('<h2>Настройки товара</h2>'+
      '<button id="v15SetPhoto" class="listbtn"><b>'+(p.image_url?'Заменить фото товара':'Добавить фото товара')+'</b><div class="muted">Фото для всех устройств</div></button>'+
      '<button id="v15SetSupplier" class="listbtn"><b>Поставщик</b><div class="muted">'+html(supplier?supplier.name:'Поставщик не назначен')+'</div></button>'+
      '<button id="v15SetSales" class="listbtn"><b>Продажи и цены</b><div class="muted">Бутылка / упаковка и порционные цены</div></button>'+
      '<button id="v15SetClose" class="secondary" style="width:100%">Закрыть</button>');
    document.getElementById('v15SetClose').onclick = closeModal;
    document.getElementById('v15SetPhoto').onclick = function () { invokeLegacy(p, 'v14Photo'); };
    document.getElementById('v15SetSales').onclick = function () { invokeLegacy(p, 'v14Edit'); };
    document.getElementById('v15SetSupplier').onclick = function () { chooseSupplierForProduct(p); };
  }

  function chooseSupplierForProduct(p) {
    var list = (S.suppliers || []).filter(function (s) { return s.active !== false; }).sort(function (a,b){return String(a.name).localeCompare(String(b.name),'ru');});
    openModal('<h2>Поставщик • '+html(p.name)+'</h2>'+
      list.map(function (s) { return '<button class="listbtn v15SupplierPick" data-id="'+html(s.id)+'"><b>'+html(s.name)+'</b></button>'; }).join('')+
      '<button id="v15NewSupplier" class="secondary" style="width:100%;margin-top:6px">+ Ввести нового поставщика</button><button id="v15SupplierCancel" class="secondary" style="width:100%;margin-top:7px">Отмена</button>');
    document.getElementById('v15SupplierCancel').onclick = function(){ openProductSettings(p); };
    document.querySelectorAll('.v15SupplierPick').forEach(function (b) {
      b.onclick = async function () {
        try {
          await api('supplier_link',{product_key:productKey(p),supplier_id:b.dataset.id,is_primary:true},true);
          await snapshot();
          var fresh = productByKey(productKey(p)) || p;
          window.v14ShowProduct(fresh);
          toast('Основной поставщик изменён');
        } catch (e) { toast(String(e && e.message ? e.message : e), true); }
      };
    });
    document.getElementById('v15NewSupplier').onclick = async function () {
      var name = await ask('Название нового поставщика');
      if (!name || !clean(name)) return;
      try {
        var created = await api('supplier_upsert',{name:clean(name)},true);
        var id = created.id;
        if (!id) throw Error('Не удалось создать поставщика');
        await api('supplier_link',{product_key:productKey(p),supplier_id:id,is_primary:true},true);
        await snapshot();
        window.v14ShowProduct(productByKey(productKey(p)) || p);
        toast('Поставщик создан и назначен');
      } catch (e) { toast(String(e && e.message ? e.message : e), true); }
    };
  }

  window.v14ShowProduct = function (p) {
    var st = statusFor(p), supplier = primarySupplier(p), lastDelivery = latestProductOperation(p,['delivery']), lastCount = latestProductOperation(p,['stocktake','spot_stocktake']);
    var prices = Array.isArray(p.portion_prices) ? p.portion_prices : [];
    var image = p.image_url ? '<img class="v15img" src="'+html(p.image_url)+'">' : '<div class="v15placeholder">▣</div>';
    var sale = [];
    if (p.sell_by_bottle === true && p.bottle_sale_price != null) sale.push(rows([['Бутылка / упаковка',moneySafe(p.bottle_sale_price)]]));
    if (p.portion_sale === true && prices.length) sale.push('<div style="display:flex;gap:6px;flex-wrap:wrap">'+prices.map(function(x){return '<span class="pill">'+html(x.ml)+' '+html(unit(p))+' · '+html(moneySafe(x.price))+'</span>';}).join('')+'</div>');
    if (!sale.length) sale.push('<div class="muted">Цены продажи пока не настроены.</div>');
    var cost = p.default_cost == null ? null : Number(p.default_cost), size = Number(p.package_size || 0), base = cost != null && size > 0 ? cost / size : null, bottle = p.bottle_sale_price == null ? null : Number(p.bottle_sale_price), profit = cost != null && bottle != null ? bottle - cost : null, margin = profit != null && bottle ? profit / bottle * 100 : null;
    var audits = (S.catalog_audit || []).filter(function(a){return a.product_key===productKey(p);}).slice(0,12);
    openModal('<div class="v15hero">'+image+'<div><div class="v15title">'+html(p.name)+'</div><div class="v15cat">'+html(p.category_name)+'</div>'+(p.barcode?'<div class="muted">Код '+html(p.barcode)+'</div>':'')+'<div class="v15qty">'+(init(p)?html(parts(qty(p),p)):'Остаток не введён')+'</div><span class="v15status '+st.cls+'">'+st.text+'</span></div><button id="v15Gear" class="v15gear" aria-label="Настройки товара">'+gearSvg()+'</button></div>'+
      '<div class="v15grid"><div class="v15box"><div class="v15head">Склад</div>'+rows([['Сейчас',init(p)?parts(qty(p),p):'Не введён'],['Минимум',parts(Number(p.minimum_amount||0),p)],['Последний переучёт',lastCount?dt(lastCount.created_at):'—'],['Последнее движение',movementLabel(p)]])+'</div><div class="v15box"><div class="v15head">Закупка</div>'+rows([['Поставщик',supplier?supplier.name:'Поставщик не назначен'],['Последняя цена',moneySafe(p.default_cost,p.cost_currency)],['Последняя поставка',lastDelivery?dt(lastDelivery.created_at):'—']])+'</div></div>'+
      '<div class="v15box" style="margin-top:8px"><div class="v15head">Продажа</div>'+sale.join('')+'</div>'+
      '<button id="v15Stocktake" style="width:100%;margin-top:10px">ПЕРЕУЧЕСТЬ ТОВАР</button>'+
      '<details class="v15box" style="margin-top:8px"><summary style="font-weight:900">Экономика</summary>'+rows([['Закупка за упаковку',moneySafe(cost)],['Себестоимость 1 '+unit(p),moneySafe(base)],['Прибыль с бутылки',moneySafe(profit)],['Маржа',margin==null?'—':margin.toFixed(1).replace('.',',')+'%']])+'</details>'+
      '<details class="v15box" style="margin-top:8px"><summary style="font-weight:900">История карточки</summary>'+(audits.length?audits.map(function(a){return '<div style="border-top:1px solid #294233;padding:7px 0"><b>Изменение карточки</b><div class="muted">'+dt(a.created_at)+(a.actor?' • '+html(a.actor):'')+'</div></div>';}).join(''):'<div class="muted">Изменений пока нет.</div>')+'</details>'+
      '<button id="v15CloseProduct" class="secondary" style="width:100%;margin-top:8px">Закрыть</button>');
    document.getElementById('v15Gear').onclick = function(){ openProductSettings(p); };
    document.getElementById('v15Stocktake').onclick = function(){ invokeLegacy(p,'v14Spot'); };
    document.getElementById('v15CloseProduct').onclick = closeModal;
  };

  function stockProducts() {
    var q = lower(state.stockSearch), category = state.stockCategory;
    return (S.products || []).filter(function (p) {
      if (p.active === false) return false;
      if (category && p.category_name !== category) return false;
      return !q || lower(p.name+' '+p.category_name+' '+(p.barcode||'')).indexOf(q) >= 0;
    }).sort(categorySort);
  }
  function stockGroups() {
    var groups = [];
    stockProducts().forEach(function (p) {
      var last = groups[groups.length-1];
      if (!last || last.name !== p.category_name) { last = {name:p.category_name, items:[]}; groups.push(last); }
      last.items.push(p);
    });
    return groups;
  }
  function stockCard(p, detailed) {
    var supplier = primarySupplier(p), price = currentSupplierPrice(p);
    if (!detailed) return '<button class="listbtn v15OpenProduct" data-key="'+html(productKey(p))+'"><div class="row"><div class="grow"><div class="name">'+html(p.name)+'</div></div><b>'+html(init(p)?parts(qty(p),p):'—')+'</b></div></button>';
    return '<button class="listbtn v15OpenProduct" data-key="'+html(productKey(p))+'"><div class="name">'+html(p.name)+'</div><div class="amount">'+html(init(p)?parts(qty(p),p):'Остаток не введён')+'</div><div class="muted" style="margin-top:5px">Поставщик: '+html(supplier?supplier.name:'не назначен')+' • закупка '+html(moneySafe(price))+' • продажа '+html(p.bottle_sale_price==null?'—':moneySafe(p.bottle_sale_price))+'</div></button>';
  }
  function renderStockV15() {
    var groups = stockGroups();
    var categories = Array.from(new Set((S.products||[]).filter(function(p){return p.active!==false;}).sort(categorySort).map(function(p){return p.category_name;})));
    var body = groups.map(function (g) {
      var content;
      if (state.stockView === 'table') {
        content = '<div style="overflow:auto"><table class="v15table"><thead><tr><th>Товар</th><th>Остаток</th><th>Поставщик</th><th>Закупка</th><th>Продажа</th></tr></thead><tbody>'+g.items.map(function(p){var s=primarySupplier(p);return '<tr class="v15OpenProduct" data-key="'+html(productKey(p))+'"><td><b>'+html(p.name)+'</b></td><td>'+html(init(p)?parts(qty(p),p):'—')+'</td><td>'+html(s?s.name:'—')+'</td><td>'+html(moneySafe(currentSupplierPrice(p)))+'</td><td>'+html(p.bottle_sale_price==null?'—':moneySafe(p.bottle_sale_price))+'</td></tr>';}).join('')+'</tbody></table></div>';
      } else content = g.items.map(function(p){return stockCard(p,state.stockView==='detailed');}).join('');
      return '<div class="v15category"><span>'+html(g.name)+'</span><small>'+g.items.length+' поз.</small></div>'+content;
    }).join('');
    document.getElementById('app').innerHTML = '<section class="section active"><div class="toolbar"><input id="v15StockSearch" class="input grow" placeholder="Название / код" value="'+html(state.stockSearch)+'"><select id="v15StockCat" class="input" style="max-width:190px"><option value="">Все категории</option>'+categories.map(function(c){return '<option '+(c===state.stockCategory?'selected':'')+'>'+html(c)+'</option>';}).join('')+'</select></div><div class="toolbar"><button class="secondary v15View" data-view="compact">Компактно</button><button class="secondary v15View" data-view="detailed">Подробно</button><button class="secondary v15View" data-view="table">Таблица</button><button id="v15StockPdf" class="secondary">PDF</button></div><div class="muted">Категории → товары по алфавиту</div>'+body+'</section>';
    document.getElementById('v15StockSearch').oninput = function(e){state.stockSearch=e.target.value;renderStockV15();};
    document.getElementById('v15StockCat').onchange = function(e){state.stockCategory=e.target.value;renderStockV15();};
    document.querySelectorAll('.v15View').forEach(function(b){b.onclick=function(){state.stockView=b.dataset.view;localStorage.setItem('bali-v15-stock-view',state.stockView);renderStockV15();};});
    document.getElementById('v15StockPdf').onclick = printSection;
    document.querySelectorAll('.v15OpenProduct').forEach(function(el){el.onclick=function(){var p=productByKey(el.dataset.key);if(p)window.v14ShowProduct(p);};});
  }

  async function loadRequests() {
    if (state.requestsLoading) return;
    state.requestsLoading = true;
    try {
      var headers = {apikey:KEY,Accept:'application/json'};
      var base = 'https://mvnxfouyoynqyjdpcblh.supabase.co/rest/v1/';
      var responses = await Promise.all([
        fetch(base+'stock_purchase_requests?select=id,supplier_id,status,created_by,comment,created_at,updated_at&order=created_at.desc&limit=200',{headers:headers,cache:'no-store'}),
        fetch(base+'stock_purchase_request_lines?select=id,request_id,product_key,suggested_quantity,requested_quantity,received_quantity,unit_cost,comment&order=id.asc',{headers:headers,cache:'no-store'})
      ]);
      if (!responses[0].ok || !responses[1].ok) throw Error('HTTP '+responses[0].status+'/'+responses[1].status);
      var requests = await responses[0].json(), lines = await responses[1].json(), by = {};
      lines.forEach(function(l){(by[l.request_id]||(by[l.request_id]=[])).push(l);});
      state.requests = requests.map(function(r){r.lines=by[r.id]||[];return r;});
      state.requestsLoaded = true;
    } catch (e) { toast('Не удалось загрузить заявки: '+String(e&&e.message?e.message:e),true); }
    state.requestsLoading = false;
  }
  function requestOpen(r){return ['confirmed','sent','partial'].indexOf(r.status)>=0;}
  function outstandingFor(p){var k=productKey(p),total=0;state.requests.forEach(function(r){if(!requestOpen(r))return;(r.lines||[]).forEach(function(l){if(l.product_key===k)total+=Math.max(0,Number(l.requested_quantity||0)-Number(l.received_quantity||0));});});return total;}
  function recommendedBase(p){if(!init(p))return 0;var desired=Number(p.target_amount||0)>0?Number(p.target_amount):Number(p.minimum_amount||0);return Math.max(0,desired-qty(p)-outstandingFor(p));}
  function recommendedPackages(p){var q=recommendedBase(p);return q>0?Math.ceil(q/packageBase(p)):0;}
  function selectedPackages(p){var k=productKey(p);return Object.prototype.hasOwnProperty.call(state.purchaseQty,k)?Number(state.purchaseQty[k]):recommendedPackages(p);}
  function requestNumber(r){var d=new Date(r.created_at),s=String(r.id||'').replace(/-/g,'').slice(0,4).toUpperCase();return 'ЗАК-'+d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+String(d.getDate()).padStart(2,'0')+'-'+s;}
  function requestStatus(s){return {draft:'Черновик',confirmed:'Подтверждена',sent:'Отправлена',partial:'Частично поставлена',completed:'Выполнена',cancelled:'Отменена'}[s]||s;}
  function purchaseProducts() {
    var q=lower(state.purchaseSearch),supplier=state.purchaseSupplier;
    return (S.products||[]).filter(function(p){if(p.active===false)return false;if(state.purchaseTab!=='all'&&!init(p))return false;var sp=primarySupplier(p);if(supplier&&(!sp||sp.id!==supplier))return false;if(q&&lower(p.name+' '+p.category_name+' '+(p.barcode||'')+' '+(sp?sp.name:'')).indexOf(q)<0)return false;return state.purchaseTab==='all'||recommendedBase(p)>0||selectedPackages(p)>0;}).sort(categorySort);
  }
  function renderPurchaseCard(p){
    var initialized=init(p),sp=primarySupplier(p),rec=recommendedPackages(p),selected=selectedPackages(p),ordered=outstandingFor(p),price=currentSupplierPrice(p),estimate=price==null?null:price*selected;
    return '<div class="card"><div class="row"><div class="grow"><div class="name">'+html(p.name)+'</div><div class="muted">'+html(sp?sp.name:'Поставщик не назначен')+'</div></div><b>'+html(moneySafe(price))+'</b></div><div class="muted" style="margin-top:6px">Сейчас: '+html(initialized?parts(qty(p),p):'остаток не введён')+' • минимум '+html(parts(Number(p.minimum_amount||0),p))+(Number(p.target_amount||0)>0?' • цель '+html(parts(Number(p.target_amount),p)):'')+' • уже заказано '+html(ordered?parts(ordered,p):'0')+'</div><div class="row" style="margin-top:9px"><div class="grow"><b>'+(initialized?'Рекомендуется: '+rec+' '+packageName(p):'Рекомендация — после первичного переучёта')+'</b></div><div class="v15counter"><button class="secondary v15Minus" data-key="'+html(productKey(p))+'">−</button><b>'+selected+' '+packageName(p)+'</b><button class="v15Plus" data-key="'+html(productKey(p))+'">+</button></div></div>'+(estimate!=null&&selected>0?'<div class="muted" style="text-align:right;margin-top:5px">≈ '+html(moneySafe(estimate))+'</div>':'')+'</div>';
  }
  function renderRequests() {
    if (!state.requests.length) return '<div class="card">Заявок пока нет.</div>';
    return state.requests.map(function(r){var s=supplierById(r.supplier_id),req=0,rec=0;(r.lines||[]).forEach(function(l){req+=Number(l.requested_quantity||0);rec+=Number(l.received_quantity||0);});var pct=req?Math.min(100,Math.round(rec/req*100)):0;return '<div class="card"><div class="row"><div class="grow"><div class="name">'+html(requestNumber(r))+'</div><div class="muted" style="color:'+GREEN+'">'+html(s?s.name:'Поставщик не указан')+'</div></div><span class="pill">'+html(requestStatus(r.status))+'</span></div><div class="muted" style="margin-top:6px">'+dt(r.created_at)+' • '+(r.lines||[]).length+' поз.'+(r.status==='partial'||r.status==='completed'?' • принято '+pct+'%':'')+'</div>'+(r.status==='confirmed'?'<button class="secondary v15MarkSent" data-id="'+html(r.id)+'" style="width:100%;margin-top:8px">ОТМЕТИТЬ КАК ОТПРАВЛЕННУЮ</button>':'')+'</div>';}).join('');
  }
  async function renderPurchasesV15() {
    if (!state.requestsLoaded && !state.requestsLoading) await loadRequests();
    if (tab !== 'buy') return;
    var activeSuppliers=(S.suppliers||[]).filter(function(s){return s.active!==false;}).sort(function(a,b){return String(a.name).localeCompare(String(b.name),'ru');});
    var header='<div class="toolbar" style="overflow-x:auto;flex-wrap:nowrap"><button class="secondary v15PTab" data-tab="needed">Нужно заказать</button><button class="secondary v15PTab" data-tab="all">Все товары</button><button class="secondary v15PTab" data-tab="requests">Заявки</button></div>';
    if(state.purchaseTab==='requests'){
      document.getElementById('app').innerHTML='<section class="section active"><h2>Закупки</h2>'+header+renderRequests()+'</section>';
    }else{
      var products=purchaseProducts(),groups=[];products.forEach(function(p){var g=groups[groups.length-1];if(!g||g.name!==p.category_name){g={name:p.category_name,items:[]};groups.push(g);}g.items.push(p);});
      var selected=(S.products||[]).filter(function(p){return p.active!==false&&selectedPackages(p)>0;}),total=0;selected.forEach(function(p){var price=currentSupplierPrice(p);if(price!=null)total+=price*selectedPackages(p);});
      var uninitialized=(S.products||[]).filter(function(p){return p.active!==false&&!init(p);}).length;
      var emptyNote=state.purchaseTab==='needed'&&products.length===0&&uninitialized>0?'<div class="card"><b>Рекомендации появятся после первичного переучёта.</b><div class="muted" style="margin-top:6px">Полный ассортимент уже доступен во вкладке «Все товары» — количество можно указать вручную.</div></div>':'';
      document.getElementById('app').innerHTML='<section class="section active"><h2>Закупки</h2>'+header+'<div class="card"><div class="row"><div class="grow"><b>Заявка: '+selected.length+' поз.</b><div class="muted">≈ '+html(moneySafe(total))+'</div></div><button id="v15PurchasePdf" class="secondary">PDF</button><button id="v15CreateRequests">СФОРМИРОВАТЬ</button></div></div><div class="toolbar"><input id="v15PurchaseSearch" class="input grow" placeholder="Товар, код или поставщик" value="'+html(state.purchaseSearch)+'"><select id="v15PurchaseSupplier" class="input" style="max-width:210px"><option value="">Все поставщики</option>'+activeSuppliers.map(function(s){return '<option value="'+html(s.id)+'" '+(s.id===state.purchaseSupplier?'selected':'')+'>'+html(s.name)+'</option>';}).join('')+'</select></div>'+emptyNote+groups.map(function(g){return '<div class="v15category"><span>'+html(g.name)+'</span><small>'+g.items.length+'</small></div>'+g.items.map(renderPurchaseCard).join('');}).join('')+'</section>';
      document.getElementById('v15PurchaseSearch').oninput=function(e){state.purchaseSearch=e.target.value;renderPurchasesV15();};
      document.getElementById('v15PurchaseSupplier').onchange=function(e){state.purchaseSupplier=e.target.value;renderPurchasesV15();};
      document.getElementById('v15PurchasePdf').onclick=printSection;
      document.getElementById('v15CreateRequests').onclick=createRequestsV15;
      document.querySelectorAll('.v15Minus').forEach(function(b){b.onclick=function(){var p=productByKey(b.dataset.key),v=selectedPackages(p);state.purchaseQty[b.dataset.key]=Math.max(0,v-1);renderPurchasesV15();};});
      document.querySelectorAll('.v15Plus').forEach(function(b){b.onclick=function(){var p=productByKey(b.dataset.key),v=selectedPackages(p);state.purchaseQty[b.dataset.key]=v+1;renderPurchasesV15();};});
    }
    document.querySelectorAll('.v15PTab').forEach(function(b){b.onclick=function(){state.purchaseTab=b.dataset.tab;renderPurchasesV15();};});
    document.querySelectorAll('.v15MarkSent').forEach(function(b){b.onclick=async function(){try{var emp=await ask('ФИО сотрудника');if(!emp)return;await api('purchase_request_status',{id:b.dataset.id,status:'sent',employee:clean(emp)},true);state.requestsLoaded=false;await snapshot();await loadRequests();renderPurchasesV15();toast('Заявка отмечена как отправленная');}catch(e){toast(String(e&&e.message?e.message:e),true);}};});
  }
  async function createRequestsV15(){
    var selected=(S.products||[]).filter(function(p){return p.active!==false&&selectedPackages(p)>0;});
    if(!selected.length){toast('Не выбраны товары',true);return;}
    var missing=selected.filter(function(p){return !primarySupplier(p);});
    if(missing.length){toast('У '+missing.length+' позиций не назначен поставщик. Откройте карточку товара → ⚙.',true);return;}
    var emp=await ask('ФИО сотрудника');if(!emp)return;
    var groups={};selected.forEach(function(p){var sid=primarySupplier(p).id;(groups[sid]||(groups[sid]=[])).push(p);});
    try{
      for(var sid in groups){var items=groups[sid];var out=await api('purchase_request_create',{employee:clean(emp),supplier_id:sid,comment:'Сформировано в BALI STOCK',lines:items.map(function(p){return{product_key:productKey(p),suggested_quantity:recommendedBase(p),requested_quantity:selectedPackages(p)*packageBase(p),unit_cost:currentSupplierPrice(p)};})},true);if(out.id)await api('purchase_request_status',{id:out.id,status:'confirmed',employee:clean(emp)},true);}
      state.purchaseQty={};state.requestsLoaded=false;await snapshot();await loadRequests();state.purchaseTab='requests';renderPurchasesV15();toast('Заявки сформированы по поставщикам');
    }catch(e){toast(String(e&&e.message?e.message:e),true);}
  }

  function normalizeInvoiceText(v){return lower(v).replace(/ё/g,'е').replace(/[^a-zа-я0-9]+/g,' ').replace(/\s+/g,' ').trim();}
  function invoiceLooksValid(raw){
    var text=normalizeInvoiceText(raw),doc=['товарно транспортная накладная','товарная накладная','накладная','ттн','тн 2','invoice','счет фактура'],table=['наименование','количество','кол во','цена','сумма','ед изм'],business=['поставщик','грузоотправитель','получатель','покупатель','унп'],hasDoc=doc.some(function(x){return text.indexOf(x)>=0;}),tc=table.filter(function(x){return text.indexOf(x)>=0;}).length,bc=business.filter(function(x){return text.indexOf(x)>=0;}).length,productHits=0;
    (S.products||[]).some(function(p){if(normalizeInvoiceText(p.name).length>=4&&text.indexOf(normalizeInvoiceText(p.name))>=0)productHits++;return productHits>=3;});
    return hasDoc ? (tc>=1||bc>=1||productHits>=1) : (tc>=3&&bc>=1);
  }
  function invoiceOverlay(show, stage){
    var old=document.getElementById('v15OcrOverlay');if(old)old.remove();if(!show)return;
    var div=document.createElement('div');div.id='v15OcrOverlay';div.className='v15overlay';div.innerHTML='<div class="v15overlayBox"><div class="v15spinner"></div><b style="font-size:18px">Распознаю накладную…</b><div id="v15OcrStage" class="muted" style="margin-top:7px">'+html(stage||'Проверяю документ')+'</div></div>';document.body.appendChild(div);
  }
  async function reduceInvoiceImage(file){
    try{
      var bitmap=await createImageBitmap(file),max=1800,scale=Math.min(1,max/Math.max(bitmap.width,bitmap.height));if(scale>=.999)return file;var canvas=document.createElement('canvas');canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);var ctx=canvas.getContext('2d');ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);if(bitmap.close)bitmap.close();return await new Promise(function(resolve){canvas.toBlob(function(blob){resolve(blob||file);},'image/jpeg',.82);});
    }catch(_){return file;}
  }
  function costFromInvoiceLine(line,packages){var values=(line.match(/\d{1,7}[.,]\d{2,4}/g)||[]).map(function(x){return Number(x.replace(',','.'));}).filter(function(x){return x>.01&&x<1000000;});if(!values.length)return null;if(packages>0&&values.length>1){for(var i=0;i<values.length;i++)for(var j=i+1;j<values.length;j++){if(Math.abs(values[i]*packages-values[j])/Math.max(1,values[j])<.06)return values[i];}}return values[0];}
  function detectSupplierFromText(raw){var t=normalizeInvoiceText(raw),best=null,bestScore=0;(S.suppliers||[]).filter(function(s){return s.active!==false;}).forEach(function(s){var name=normalizeInvoiceText(s.name);if(name&&t.indexOf(name)>=0){best=s;bestScore=2;return;}var tokens=name.split(' ').filter(function(x){return x.length>2;}),hits=tokens.filter(function(x){return t.indexOf(x)>=0;}).length,score=tokens.length?hits/tokens.length:0;if(score>=.66&&score>bestScore){best=s;bestScore=score;}});return best;}
  function invoiceNumber(raw){var m=/(?:ттн|тн|накладн\w*|invoice)\s*(?:№|no\.?|номер)?\s*[:#№-]?\s*([a-zа-я0-9][a-zа-я0-9/\-.]{1,23})/i.exec(raw);return m?m[1]:'';}
  async function runOcrV15(){
    if(!delivery.file){toast('Сначала выберите фото накладной',true);return;}
    var worker=null;
    try{
      invoiceOverlay(true,'Подготавливаю изображение');
      var image=await reduceInvoiceImage(delivery.file);
      worker=await Tesseract.createWorker(['rus','eng'],1,{logger:function(m){var el=document.getElementById('v15OcrStage');if(el&&m&&m.status)el.textContent=m.status==='recognizing text'?'Распознаю текст…':'Подготавливаю OCR…';}});
      var result=await worker.recognize(image);await worker.terminate();worker=null;
      var raw=result.data.text||'';
      if(!invoiceLooksValid(raw)){
        delivery.rawText='';delivery.lines=[];invoiceOverlay(false);var stateEl=document.getElementById('ocrState');if(stateEl)stateEl.textContent='Накладная не распознана';toast('Накладная не распознана. Загрузите оригинальную накладную.',true);return;
      }
      var lines=raw.split(/\r?\n/).map(function(x){return x.replace(/\s+/g,' ').trim();}).filter(function(x){return x.length>2;}),found=[];
      (S.products||[]).filter(function(p){return p.active!==false;}).forEach(function(p){var bi=-1,bs=0;for(var i=0;i<lines.length;i++){var score=matchScore(p.name,lines[i]);if(score>bs){bs=score;bi=i;}}if(bs<.5||bi<0)return;var q=qFromLine(lines[bi],p);if(!q)return;found.push({product_key:productKey(p),whole:q.whole,extra:q.extra,cost:costFromInvoiceLine(lines[bi],q.whole),source:lines[bi],confidence:bs*.72+q.conf*.28,corrected:false});});
      if(!found.length){delivery.rawText='';delivery.lines=[];invoiceOverlay(false);toast('Накладная не распознана. Загрузите оригинальную накладную.',true);return;}
      found.sort(function(a,b){return categorySort(productByKey(a.product_key),productByKey(b.product_key));});
      delivery.rawText=raw;delivery.lines=found.slice(0,120);var supplier=detectSupplierFromText(raw);delivery.__v15SupplierId=supplier?supplier.id:'';delivery.__v15Doc=invoiceNumber(raw);invoiceOverlay(false);render();toast('Накладная распознана: '+delivery.lines.length+' поз. Проверьте количество и цены.');
    }catch(e){if(worker)try{await worker.terminate();}catch(_){}invoiceOverlay(false);toast('Не удалось распознать накладную. '+String(e&&e.message?e.message:e),true);var el=document.getElementById('ocrState');if(el)el.textContent='Ошибка распознавания';}
  }
  window.runOcr = runOcrV15;

  var originalSubmitDelivery = window.submitDelivery || submitDelivery;
  window.submitDelivery = async function(){
    var supplier=document.getElementById('delSup'),location=document.getElementById('delLoc');
    if(supplier&&!supplier.value){toast('Выберите поставщика из списка.',true);return;}
    if(location&&!location.value){toast('Выберите склад.',true);return;}
    return originalSubmitDelivery();
  };

  function enhanceDeliveryV15(){
    var emp=document.getElementById('delEmp'),sup=document.getElementById('delSup'),loc=document.getElementById('delLoc'),doc=document.getElementById('delDoc'),add=document.getElementById('addSup'),ocr=document.getElementById('ocrBtn'),submit=document.getElementById('submitDelivery');
    if(!emp||!sup)return;
    emp.placeholder='ФИО принимающего *';
    if(sup.options.length)sup.options[0].textContent='Выберите поставщика *';
    if(delivery.__v15SupplierId)sup.value=delivery.__v15SupplierId;
    if(doc){doc.placeholder='№ накладной / ТТН';if(delivery.__v15Doc&&!doc.value)doc.value=delivery.__v15Doc;}
    if(add)add.style.display='none';
    function wrap(select,labelText,id){if(!select||document.getElementById(id))return;var parent=select.parentNode,wrap=document.createElement('div');wrap.id=id;var label=document.createElement('div');label.className='muted';label.style='margin-bottom:4px;font-weight:800';label.textContent=labelText;parent.insertBefore(wrap,select);wrap.appendChild(label);wrap.appendChild(select);}
    wrap(sup,'Поставщик *','v15SupWrap');wrap(loc,'Склад *','v15LocWrap');
    if(ocr)ocr.onclick=runOcrV15;
    if(submit)submit.onclick=window.submitDelivery;
  }

  function enhanceCurrent(){
    if(tab==='stock'){renderStockV15();return;}
    if(tab==='buy'){renderPurchasesV15();return;}
    if(tab==='delivery'){enhanceDeliveryV15();}
  }
  var priorRender = render;
  render = function(){priorRender();setTimeout(enhanceCurrent,0);};
  ensureCss();
  setTimeout(enhanceCurrent,50);
})();
