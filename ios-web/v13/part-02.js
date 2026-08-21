  html=html.replace('<div class="toolbar">','<div class="toolbar"><button id="v13DelScan" class="secondary">📷 Товар по коду</button><button id="v13DelManualCode" class="secondary">⌨️ Код вручную</button>');
  return html;
};
wireDelivery = function(){
  __v13PrevWireDelivery();
  const scan=$('#v13DelScan'), manual=$('#v13DelManualCode');
  const addByCode=async code=>{if(!code)return;const resolved=await __v12ResolveProductCode(code);const p=resolved&&resolved.product;if(!p)return;const q=await quantityFor(p,'Поставка');if(!q)return;delivery.lines.push({product_key:keyOf(p),whole:p.stock_unit==='pcs'?q.quantity_base:Math.floor(q.quantity_base/p.package_size),extra:p.stock_unit==='pcs'?0:q.quantity_base%p.package_size,cost:null,corrected:true});render()};
  if(scan)scan.onclick=async()=>addByCode(await __v13ScanCodeRaw()); if(manual)manual.onclick=async()=>addByCode(await ask('Введите QR / штрихкод'));
};

// ---------- Stocktake: category filter, scanner, wall-clock duration ----------
const __v13PrevWireCount = wireCount;
wireCount = function(){
  __v13PrevWireCount();
  clearInterval(__v13WallTimer); __v13WallTimer=null;
  if(!count)return;
  count.categoryFilter=count.categoryFilter||'';
  document.querySelectorAll('.cw,.ce,.cc').forEach(x=>x.addEventListener('input',()=>{count.lastProductKey=x.dataset.key||count.lastProductKey||null},true));
  const search=$('#cntSearch');
  if(search){
    const row=search.parentElement;
    if(row&&!$('#v13CountCat')){
      const box=document.createElement('div');box.className='v13-filterbar';
      box.innerHTML=`<select id="v13CountCat" class="input"><option value="">Все категории</option>${__v13Categories().map(c=>`<option value="${esc(c)}" ${count.categoryFilter===c?'selected':''}>${esc(c)}</option>`).join('')}</select><div class="toolbar"><button id="v13CountScan" class="secondary">📷 Найти по коду</button><button id="v13CountCode" class="secondary">⌨️ Код</button></div>`;
      row.insertAdjacentElement('afterend',box);
      $('#v13CountCat').onchange=e=>{count.categoryFilter=e.target.value;__v13ApplyCountCategory()};
      const findCode=async code=>{if(!code)return;const resolved=await __v12ResolveProductCode(code);const p=resolved&&resolved.product;if(!p)return;count.categoryFilter=p.category_name;count.search=p.name;render()};
      $('#v13CountScan').onclick=async()=>findCode(await __v13ScanCodeRaw()); $('#v13CountCode').onclick=async()=>findCode(await ask('Введите QR / штрихкод'));
    }
    __v13ApplyCountCategory();
  }
  const time=$('#countTime'); if(time&&time.parentElement&&!$('#v13WallTime')){time.parentElement.insertAdjacentHTML('beforeend','<br>Общее время: <span id="v13WallTime"></span>');}
  const update=()=>{const el=$('#v13WallTime');if(!el||!count)return;const sec=Math.max(0,Math.floor((Date.now()-new Date(count.started_at).getTime())/1000));el.textContent=dur(sec)}; update();__v13WallTimer=setInterval(update,1000);
};
function __v13ApplyCountCategory(){
  if(!count)return; const wanted=count.categoryFilter||''; const first=$('#app .cat'); if(!first)return; const parent=first.parentElement; if(!parent)return;
  let current='',show=true;
  [...parent.children].forEach(el=>{if(el.classList.contains('cat')){current=(el.querySelector('span')?.textContent||'').trim();show=!wanted||current===wanted;el.style.display=show?'':'none'}else if(el.classList.contains('card'))el.style.display=show?'':'none'});
}

// ---------- Multi-line write-off and transfer ----------
writeoff = async function(){
  try{await api('authorize',{},true);const emp=await ask('ФИО сотрудника');if(!emp)return;const reason=await ask('Причина списания','text','Бой / порча');if(!reason)return;const loc=await __v13ChooseLocation('Место списания') || (S.locations.find(x=>x.is_primary)||S.locations[0])?.id;const lines=await __v13CollectOperationLines('Списание');if(!lines.length)return;const comment=await ask('Комментарий (необязательно)')||null;await api('writeoff',{employee:emp,reason,location_id:loc||null,comment,lines},true);toast(navigator.onLine?'Списание проведено':'Списание сохранено на iPhone и ждёт синхронизации');await snapshot().catch(()=>{});setTab('stock')}catch(e){toast(e.message,true)}
};
transfer = async function(){
  try{if((S.locations||[]).filter(x=>x.active!==false).length<2)throw Error('Добавьте минимум два места хранения');await api('authorize',{},true);const emp=await ask('ФИО сотрудника');if(!emp)return;const src=await __v13ChooseLocation('Откуда перемещаем');if(!src)return;const dst=await __v13ChooseLocation('Куда перемещаем',src);if(!dst)return;const lines=await __v13CollectOperationLines('Перемещение');if(!lines.length)return;const comment=await ask('Комментарий (необязательно)')||null;await api('transfer',{employee:emp,source_location_id:src,target_location_id:dst,comment,lines},true);toast(navigator.onLine?'Перемещение проведено':'Перемещение сохранено на iPhone и ждёт синхронизации');await snapshot().catch(()=>{});setTab('stock')}catch(e){toast(e.message,true)}
};

// ---------- Catalog administration ----------
async function __v13CatalogPost(action,body){
  if(!navigator.onLine)throw Error('Изменение каталога требует подключения к интернету. Остатки и складские операции при этом по-прежнему работают офлайн.');
  await api('authorize',{},true); if(!pin)throw Error('PIN не введён');
  const r=await fetch(V13_CATALOG_API,{method:'POST',headers:{apikey:KEY,Accept:'application/json','Content-Type':'application/json','x-bali-stock-pin':pin},body:JSON.stringify({action,...body})});
  const d=await r.json().catch(()=>({}));if(!r.ok)throw Error(d.error||`HTTP ${r.status}`);return d;
}
async function __v13AddProduct(){
