import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const UPSTREAM = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-ios";

const headers = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  "Pragma": "no-cache",
  "Expires": "0",
  "Access-Control-Allow-Origin": "*",
};

function icon(path: string) {
  return `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;
}

const icons = {
  home: icon('<path d="M2.8 9.2 12 3.5l9.2 5.7V20H2.8V9.2Z"/><path d="M5 9.5h14M7 11v9M17 11v9M7 14h10M7 17h10"/>'),
  stock: icon('<rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M4.5 10h15M4.5 15h15M6 6h4v3M13.5 11.5h4V14M8.5 16.5h5V19"/>'),
  stocktake: icon('<rect x="5" y="4.5" width="14" height="16" rx="2"/><rect x="8.5" y="2.8" width="7" height="3.6" rx="1"/><path d="M8 9h8M8 14l2.7 2.5 6.1-5.5"/>'),
  purchases: icon('<path d="M3 5h2.5l1.7 10.2h10.3L20 8H6M9 19h.1M17 19h.1"/>'),
  delivery: icon('<rect x="2.5" y="7" width="11.5" height="9" rx="1.4"/><path d="M14 10h4.2l2.8 3v3h-7V10ZM16.2 11.1h2l1.6 1.9M9 18h7"/><circle cx="7" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>'),
  settings: icon('<path d="M8 3.2h8L21 8v8l-5 4.8H8L3 16V8l5-4.8Z"/><circle cx="12" cy="12" r="3.2"/><path d="M12 5.8v2.4M12 15.8v2.4M5.8 12h2.4M15.8 12h2.4"/>'),
};

const scannerEnhancement = `<script id="bali-v14-scan-workflows">
(function(){
  'use strict';
  window.__BALI_V14_SCAN_WORKFLOWS__='v14.4';

  function clean(v){return String(v==null?'':v).trim()}
  function lower(v){return clean(v).toLowerCase()}
  function byCode(code){var wanted=lower(code);if(!wanted)return null;return (S.products||[]).find(function(p){return lower(p.barcode)===wanted})||null}
  function productForKey(k){return (S.products||[]).find(function(p){return keyOf(p)===k})||null}
  function validCost(v){var t=clean(v).replace(',','.');return t!==''&&Number.isFinite(Number(t))&&Number(t)>=0}

  async function scanCodeFor(onCode){
    if(typeof Html5Qrcode==='undefined'){toast('Модуль камеры не загрузился. Используйте «Ввести код товара».',true);return}
    openModal('<h2>Сканировать товар</h2><div class="muted" style="margin-bottom:10px">Наведите камеру на QR-код или штрихкод товара.</div><div id="v14FlowReader" style="width:100%;min-height:260px;border-radius:14px;overflow:hidden"></div><button id="v14FlowStop" class="secondary" style="width:100%;margin-top:12px">Закрыть сканер</button>');
    document.getElementById('v14FlowStop').onclick=closeModal;
    try{
      var scanner=new Html5Qrcode('v14FlowReader');
      window.__baliProductScanner=scanner;
      var handled=false;
      await scanner.start({facingMode:'environment'},{fps:10,qrbox:{width:250,height:170}},async function(decoded){
        if(handled)return;
        var code=clean(decoded);if(!code)return;
        handled=true;window.__baliProductScanner=null;
        try{await scanner.stop()}catch(_){}try{scanner.clear()}catch(_){}
        closeModal();
        await onCode(code);
      },function(){});
    }catch(e){
      window.__baliProductScanner=null;closeModal();toast('Камера: '+String(e&&e.message?e.message:e),true);
    }
  }
  window.__baliScanCodeFor=scanCodeFor;
  window.startProductCodeScanner=function(){return scanCodeFor(window.handleProductCode)};
  window.enterProductCodeManually=async function(){var code=await ask('Введите код товара');if(code&&clean(code))await window.handleProductCode(clean(code))};

  async function askCodeFor(handler){var code=await ask('Введите код товара');if(!code||!clean(code))return;await handler(clean(code))}
  function unknown(code){toast('Код товара '+clean(code)+' не привязан ни к одной позиции.',true)}

  function countLineForProduct(p){return count&&count.lines?count.lines.find(function(l){return l.product_key===keyOf(p)})||null:null}
  function saveCountLine(line,whole,extra,comment){line.whole=whole;line.extra=line.stock_unit==='pcs'?0:extra;line.comment=clean(comment);line.rechecked=false;saveCount();render()}
  async function editCountLine(line,nextScan){
    var p=productForKey(line.product_key)||line;
    var filled=filledCountLine(line);
    openModal('<h2>'+esc(line.product_name)+'</h2><div class="pill '+(filled?'':'warn')+'">'+(filled?'ДАННЫЕ УЖЕ ВВЕДЕНЫ':'НЕ ВВЕДЕНО')+'</div><div class="muted" style="margin-top:8px">'+(line.before_initialized?'Расчётно: '+esc(parts(n(line.before_total),p)):'Первичный остаток')+'</div><div class="grid2" style="margin-top:12px"><input id="flowCountWhole" class="input" inputmode="numeric" value="'+esc(line.whole==null?'':line.whole)+'" placeholder="'+(line.stock_unit==='pcs'?'Количество, шт.':packLabel(p))+'"><input id="flowCountExtra" class="input" inputmode="numeric" value="'+esc(line.stock_unit==='pcs'?'0':(line.extra==null?'':line.extra))+'" '+(line.stock_unit==='pcs'?'disabled':'')+' placeholder="Доп. '+unit(p)+'"></div><textarea id="flowCountComment" class="input" style="margin-top:8px" placeholder="Комментарий">'+esc(line.comment||'')+'</textarea><div class="toolbar" style="margin-top:12px"><button id="flowCountSave">'+(nextScan?'СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН':'СОХРАНИТЬ')+'</button><button id="flowCountCancel" class="secondary">Отмена</button></div>');
    document.getElementById('flowCountCancel').onclick=closeModal;
    document.getElementById('flowCountSave').onclick=function(){
      var w=parseInt(document.getElementById('flowCountWhole').value,10),e=line.stock_unit==='pcs'?0:parseInt(document.getElementById('flowCountExtra').value,10);
      if(!Number.isFinite(w)||w<0||!Number.isFinite(e)||e<0||(line.stock_unit!=='pcs'&&e>=n(line.package_size))){toast('Проверьте фактическое количество',true);return}
      var comment=document.getElementById('flowCountComment').value;closeModal();saveCountLine(line,w,e,comment);if(nextScan)setTimeout(countScanFlow,60);
    };
  }
  async function handleCountCode(code,nextScan){var p=byCode(code);if(!p){unknown(code);if(nextScan)setTimeout(countScanFlow,80);return}var line=countLineForProduct(p);if(!line){toast('Товар '+p.name+' не входит в текущий переучёт.',true);if(nextScan)setTimeout(countScanFlow,80);return}await editCountLine(line,nextScan)}
  function countScanFlow(){if(!count)return;scanCodeFor(function(code){return handleCountCode(code,true)})}
  function applyCountDomFilter(){
    if(!count)return;
    var q=lower(count.__v14Search||''),mode=count.__v14Filter||'all';
    document.querySelectorAll('.cw').forEach(function(input){var line=count.lines.find(function(x){return x.product_key===input.dataset.key});if(!line)return;var p=productForKey(line.product_key),filled=filledCountLine(line),hay=lower(line.product_name+' '+line.category_name+' '+(p&&p.barcode?p.barcode:'')),show=(!q||hay.indexOf(q)>=0)&&(mode==='all'||(mode==='filled'&&filled)||(mode==='unfilled'&&!filled)),card=input.closest('.card');if(card)card.style.display=show?'':'none';var name=card&&card.querySelector('.name');if(name&&!name.querySelector('.v14Entered')){var tag=document.createElement('span');tag.className='pill v14Entered '+(filled?'':'warn');tag.style.marginLeft='6px';tag.textContent=filled?'ДАННЫЕ ВВЕДЕНЫ':'НЕ ВВЕДЕНО';name.appendChild(tag)}});
    document.querySelectorAll('.cat').forEach(function(cat){var next=cat.nextElementSibling;var visible=false;while(next&&!next.classList.contains('cat')){if(next.classList&&next.classList.contains('card')&&next.style.display!=='none')visible=true;next=next.nextElementSibling}cat.style.display=visible?'':'none'});
    document.querySelectorAll('.v14CountFilter').forEach(function(b){b.classList.toggle('active',b.dataset.mode===mode)});
  }
  function enhanceCount(){
    if(!count)return;
    count.onlyUnfilled=false;
    var search=document.getElementById('cntSearch');if(!search)return;
    var row=search.closest('.row');
    var tools=document.createElement('div');tools.className='toolbar';tools.innerHTML='<button id="v14CountScan">Сканировать товар</button><button id="v14CountCode" class="secondary">Ввести код товара</button>';
    row.parentNode.insertBefore(tools,row);
    var filters=document.createElement('div');filters.className='toolbar';filters.style.marginTop='8px';var filled=count.lines.filter(filledCountLine).length;filters.innerHTML='<button class="secondary v14CountFilter" data-mode="all">Все • '+count.lines.length+'</button><button class="secondary v14CountFilter" data-mode="unfilled">Не введено • '+(count.lines.length-filled)+'</button><button class="secondary v14CountFilter" data-mode="filled">Введено • '+filled+'</button>';row.parentNode.insertBefore(filters,row.nextSibling);
    var oldOnly=document.getElementById('onlyUnfilled');if(oldOnly&&oldOnly.parentElement)oldOnly.parentElement.style.display='none';
    search.placeholder='Название / категория / код товара';search.value=count.__v14Search||'';search.oninput=function(e){count.__v14Search=e.target.value;applyCountDomFilter()};
    document.getElementById('v14CountScan').onclick=countScanFlow;
    document.getElementById('v14CountCode').onclick=function(){askCodeFor(function(code){return handleCountCode(code,false)})};
    document.querySelectorAll('.v14CountFilter').forEach(function(b){b.onclick=function(){count.__v14Filter=b.dataset.mode;applyCountDomFilter()}});
    applyCountDomFilter();
  }

  function upsertDeliveryLine(p,whole,extra,cost){var key=keyOf(p),existing=delivery.lines.find(function(l){return l.product_key===key}),line={product_key:key,whole:whole,extra:p.stock_unit==='pcs'?0:extra,cost:Number(cost),corrected:true};if(existing)Object.assign(existing,line);else delivery.lines.push(line);render()}
  async function editDeliveryProduct(p,nextScan){
    var old=delivery.lines.find(function(l){return l.product_key===keyOf(p)}),whole=old?old.whole:0,extra=old?old.extra:0,cost=old&&old.cost!=null?old.cost:'';
    openModal('<h2>'+esc(p.name)+'</h2><div class="muted">'+esc(p.category_name)+' • '+esc(packSize(p))+'</div><div class="grid2" style="margin-top:12px"><input id="flowDelWhole" class="input" inputmode="numeric" value="'+esc(whole)+'" placeholder="'+(p.stock_unit==='pcs'?'Количество, шт.':packLabel(p))+'"><input id="flowDelExtra" class="input" inputmode="numeric" value="'+esc(p.stock_unit==='pcs'?'0':extra)+'" '+(p.stock_unit==='pcs'?'disabled':'')+' placeholder="Доп. '+unit(p)+'"></div><input id="flowDelCost" class="input" style="margin-top:8px" inputmode="decimal" value="'+esc(cost)+'" placeholder="Закупочная цена, BYN *"><div class="muted" style="margin-top:8px">Закупочная цена обязательна. Она обновляет последнюю фактическую цену товара.</div><div class="toolbar" style="margin-top:12px"><button id="flowDelSave">'+(nextScan?'СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН':'ДОБАВИТЬ В ПОСТАВКУ')+'</button><button id="flowDelCancel" class="secondary">Отмена</button></div>');
    document.getElementById('flowDelCancel').onclick=closeModal;
    document.getElementById('flowDelSave').onclick=function(){var w=parseInt(document.getElementById('flowDelWhole').value,10),e=p.stock_unit==='pcs'?0:parseInt(document.getElementById('flowDelExtra').value,10),c=document.getElementById('flowDelCost').value;if(!Number.isFinite(w)||w<0||!Number.isFinite(e)||e<0||(p.stock_unit!=='pcs'&&e>=n(p.package_size))||(w===0&&e===0)){toast('Проверьте количество поставки',true);return}if(!validCost(c)){toast('Укажите закупочную цену',true);return}closeModal();upsertDeliveryLine(p,w,e,String(c).replace(',','.'));if(nextScan)setTimeout(deliveryScanFlow,60)};
  }
  async function handleDeliveryCode(code,nextScan){var p=byCode(code);if(!p){unknown(code);if(nextScan)setTimeout(deliveryScanFlow,80);return}await editDeliveryProduct(p,nextScan)}
  function deliveryScanFlow(){scanCodeFor(function(code){return handleDeliveryCode(code,true)})}
  function drawDeliverySearch(){var box=document.getElementById('v14DeliveryResults');if(!box)return;var q=lower(delivery.__v14Search||'');if(!q){box.innerHTML='';return}var items=(S.products||[]).filter(function(p){return p.active!==false&&lower(p.name+' '+p.category_name+' '+(p.barcode||'')).indexOf(q)>=0}).slice(0,15);box.innerHTML=items.length?items.map(function(p){var added=delivery.lines.some(function(l){return l.product_key===keyOf(p)});return '<button class="listbtn v14DeliveryPick" data-key="'+esc(keyOf(p))+'"><div class="row"><div class="grow"><div class="name">'+esc(p.name)+'</div><div class="muted">'+esc(p.category_name)+(p.barcode?' • код '+esc(p.barcode):'')+'</div></div><span class="pill '+(added?'':'warn')+'">'+(added?'ДОБАВЛЕНО':'ДОБАВИТЬ')+'</span></div></button>'}).join(''):'<div class="card">Совпадений нет.</div>';document.querySelectorAll('.v14DeliveryPick').forEach(function(b){b.onclick=function(){var p=productForKey(b.dataset.key);if(p)editDeliveryProduct(p,false)}})}
  function enhanceDelivery(){
    var lines=document.getElementById('delLines');if(!lines)return;
    var block=document.createElement('div');block.className='card';block.innerHTML='<b>Добавить товар</b><div class="muted" style="margin:6px 0 10px">Скан камерой, код товара или поиск по названию.</div><div class="toolbar"><button id="v14DeliveryScan">Сканировать товар</button><button id="v14DeliveryCode" class="secondary">Ввести код товара</button></div><input id="v14DeliverySearch" class="input" placeholder="Название / категория / код товара"><div id="v14DeliveryResults" style="margin-top:8px"></div>';lines.parentNode.insertBefore(block,lines);
    document.getElementById('v14DeliveryScan').onclick=deliveryScanFlow;document.getElementById('v14DeliveryCode').onclick=function(){askCodeFor(function(code){return handleDeliveryCode(code,false)})};var search=document.getElementById('v14DeliverySearch');search.value=delivery.__v14Search||'';search.oninput=function(e){delivery.__v14Search=e.target.value;drawDeliverySearch()};drawDeliverySearch();
    document.querySelectorAll('#delLines .card').forEach(function(card,i){var line=delivery.lines[i],name=card.querySelector('.name');if(name&&!name.querySelector('.v14DeliveryEntered')){var tag=document.createElement('span');tag.className='pill v14DeliveryEntered';tag.style.marginLeft='6px';tag.textContent='ДАННЫЕ ВВЕДЕНЫ';name.appendChild(tag)}if(line&&!validCost(line.cost)){var warn=document.createElement('div');warn.className='error';warn.style.marginTop='6px';warn.textContent='Закупочная цена не заполнена';card.appendChild(warn)}});
    var submit=document.getElementById('submitDelivery'),missing=delivery.lines.some(function(l){return !validCost(l.cost)});if(submit&&missing){submit.disabled=true;var note=document.createElement('div');note.className='error';note.style.marginTop='8px';note.textContent='Заполните закупочную цену у каждой позиции.';submit.parentNode.insertBefore(note,submit)}
  }
  var originalSubmitDelivery=submitDelivery;
  submitDelivery=async function(){if(delivery.lines.some(function(l){return !validCost(l.cost)})){toast('Закупочная цена обязательна для каждой позиции поставки.',true);return}return originalSubmitDelivery()};

  var originalRender=render;
  render=function(){
    var savedSearch=count&&tab==='count'?(count.__v14Search||''):'';
    if(count&&tab==='count'){count.search='';count.onlyUnfilled=false}
    originalRender();
    if(tab==='count'&&count){count.__v14Search=savedSearch;enhanceCount()}
    if(tab==='delivery')enhanceDelivery();
  };
  render();
})();
</script>`;

function patchHtml(source: string) {
  let html = source;

  // Safari cannot parse the legacy pattern `if (...) return,p=...`.
  html = html.replace(/return,([A-Za-z_$][A-Za-z0-9_$]*)=/g, "return;let $1=");
  html = html.replace("(!p.stock_unit==='pcs'&&e>=p.package_size)", "(p.stock_unit!=='pcs'&&e>=p.package_size)");
  html = html.replaceAll("await ask('Введите штрихкод или QR-код')", "await ask('Введите код товара')");
  html = html.replaceAll('Поиск по названию, QR/штрихкоду или коду вручную.', 'Поиск по названию, скану камерой или коду товара.');
  html = html.replaceAll('>📷 Сканировать</button>', '>📷 Сканировать камерой</button>');
  html = html.replaceAll('<h2>Контроль</h2>', '<h2>Настройки</h2>');

  const newNav = `nav.innerHTML='<button data-tab="home" class="active"><b>${icons.home}</b>Главная</button><button data-tab="stock"><b>${icons.stock}</b>Склад</button><button data-tab="count"><b>${icons.stocktake}</b>Переучёт</button><button data-tab="buy"><b>${icons.purchases}</b>Закупки</button><button data-tab="delivery"><b>${icons.delivery}</b>Поставка</button><button data-tab="control"><b>${icons.settings}</b>Настройки</button>';`;
  html = html.replace(/nav\.innerHTML='<button data-tab="home" class="active">[\s\S]*?<\/button>';/, newNav);

  const navCss = `<style id="bali-v14-runtime-nav">.tabs b{display:grid!important;place-items:center;height:22px;margin-bottom:2px}.tabs b svg{display:block}.tabs button{line-height:1.1}.tabs button.active b{color:#39ff6a}.v14CountFilter.active{background:#39ff6a!important;color:#031408!important}</style>`;
  html = html.replace('</head>', navCss + '\n</head>');
  html = html.replace('</body>', scannerEnhancement + '\n</body>');

  return html;
}

function audit(html: string) {
  const remainingLegacy = (html.match(/return,[A-Za-z_$][A-Za-z0-9_$]*=/g) || []).length;
  const snapshotPos = html.indexOf('async function snapshot');
  const v14SnapshotPos = html.indexOf('baseSnapshot=snapshot');
  const navMatch = html.match(/nav\.innerHTML='<button data-tab="home" class="active">[\s\S]*?<\/button>';/)?.[0] || '';
  const scannerFlows = html.includes('__BALI_V14_SCAN_WORKFLOWS__') && html.includes('СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН') && html.includes('Закупочная цена обязательна для каждой позиции поставки.') && html.includes('ДАННЫЕ ВВЕДЕНЫ') && html.includes('НЕ ВВЕДЕНО');
  return {
    ok: remainingLegacy === 0 && snapshotPos >= 0 && v14SnapshotPos > snapshotPos && scannerFlows && navMatch.includes('Главная') && navMatch.includes('Склад') && navMatch.includes('Переучёт') && navMatch.includes('Закупки') && navMatch.includes('Поставка') && navMatch.includes('Настройки') && !navMatch.includes('data-tab="history"'),
    remaining_legacy_return_comma: remainingLegacy,
    snapshot_found: snapshotPos >= 0,
    snapshot_before_v14: v14SnapshotPos > snapshotPos,
    scanner_workflows: scannerFlows,
    history_in_runtime_nav: navMatch.includes('data-tab="history"'),
    runtime_nav: navMatch.replace(/<svg[\s\S]*?<\/svg>/g, '[icon]'),
  };
}

Deno.serve(async (req: Request) => {
  try {
    const response = await fetch(`${UPSTREAM}?runtime=4&ts=${Date.now()}`, {
      cache: 'no-store',
      headers: { 'User-Agent': 'BALI-STOCK-iOS-Runtime/4', Accept: 'text/html,*/*' },
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
    return new Response(`BALI STOCK runtime error: ${message}`, { status: 500, headers: { ...headers, 'Content-Type': 'text/plain; charset=utf-8' } });
  }
});
