    const okText = !q || String(card.dataset.search || '').includes(q);
    const okCat = !__v13StockFilter.category || card.dataset.category === __v13StockFilter.category;
    const okLow = !__v13StockFilter.low || card.dataset.low === '1';
    const okUninit = !__v13StockFilter.uninitialized || card.dataset.uninit === '1';
    card.classList.toggle('v13-hidden', !(okText && okCat && okLow && okUninit));
  });
  document.querySelectorAll('.v13-stock-cat').forEach(cat => {
    const body = cat.nextElementSibling;
    const visible = body && [...body.querySelectorAll('.v13-product')].some(x => !x.classList.contains('v13-hidden'));
    cat.classList.toggle('v13-hidden', !visible);
    if (body) body.classList.toggle('v13-hidden', !visible);
  });
  document.querySelectorAll('.v13-chip').forEach(b=>b.classList.toggle('active', (b.dataset.cat||'')===__v13StockFilter.category));
}
wireStock = function() {
  const pdf = $('#stockPdf'); if (pdf) pdf.onclick = printSection;
  const scan = $('#v12Scan'); if (scan) scan.onclick = __v12StartScanner;
  const manual = $('#v12ManualCode'); if (manual) manual.onclick = async()=>{ const code=await ask('Введите QR / штрихкод'); if(code) await __v12HandleCode(code); };
  const search = $('#stockSearch'); if (search) search.oninput = e=>{ __v13StockFilter.query=e.target.value; __v13ApplyStockFilters(); };
  const category = $('#v13Category'); if (category) category.onchange=e=>{ __v13StockFilter.category=e.target.value; __v13ApplyStockFilters(); };
  const low = $('#v13Low'); if (low) low.onchange=e=>{ __v13StockFilter.low=e.target.checked; __v13ApplyStockFilters(); };
  const uninit = $('#v13Uninit'); if (uninit) uninit.onchange=e=>{ __v13StockFilter.uninitialized=e.target.checked; __v13ApplyStockFilters(); };
  document.querySelectorAll('.v13-chip').forEach(b=>b.onclick=()=>{ __v13StockFilter.category=b.dataset.cat||''; if(category) category.value=__v13StockFilter.category; __v13ApplyStockFilters(); });
  document.querySelectorAll('.v13-stock-cat').forEach(h=>h.onclick=()=>{ const b=h.nextElementSibling; if(b) b.style.display=b.style.display==='none'?'':'none'; });
  document.querySelectorAll('.ph').forEach(b=>b.onclick=()=>showProductHistory(b.dataset.key));
  __v13ApplyStockFilters();
};

chooseProduct = function(title) {
  return new Promise(res=>{
    let query='', category='';
    openModal(`<h2>${esc(title)}</h2><div class="v13-filterbar"><input id="psearch" class="input" placeholder="Название / код"><select id="pcat" class="input"><option value="">Все категории</option>${__v13Categories().map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join('')}</select></div><div id="plist" class="v13-scroll"></div><button id="pcancel" class="secondary" style="width:100%">Отмена</button>`);
    const draw=()=>{
      const q=query.trim().toLowerCase();
      const ps=(S.products||[]).filter(p=>p.active!==false && (!category || p.category_name===category) && (!q || __v13ProductSearchText(p).includes(q))).slice(0,200);
      $('#plist').innerHTML=ps.map(p=>`<button class="listbtn" data-key="${esc(keyOf(p))}"><b>${esc(p.name)}</b><br><span class="muted">${esc(p.category_name)} • ${esc(packSize(p))}${p.barcode?` • ${esc(p.barcode)}`:''}</span></button>`).join('') || '<div class="muted">Ничего не найдено.</div>';
      document.querySelectorAll('#plist .listbtn').forEach(b=>b.onclick=()=>{ const p=S.products.find(x=>keyOf(x)===b.dataset.key); closeModal(); res(p||null); });
    };
    $('#psearch').oninput=e=>{query=e.target.value;draw()}; $('#pcat').onchange=e=>{category=e.target.value;draw()}; $('#pcancel').onclick=()=>{closeModal();res(null)}; draw();
  });
};

// ---------- Helpers ----------
function __v13Select(title, items, valueKey='value', labelKey='label') {
  return new Promise(res=>{
    openModal(`<h2>${esc(title)}</h2><div class="v13-scroll">${items.map(x=>`<button class="listbtn v13-select" data-value="${esc(x[valueKey])}"><b>${esc(x[labelKey])}</b>${x.sub?`<br><span class="muted">${esc(x.sub)}</span>`:''}</button>`).join('')}</div><button id="v13SelectCancel" class="secondary" style="width:100%">Отмена</button>`);
    document.querySelectorAll('.v13-select').forEach(b=>b.onclick=()=>{const v=b.dataset.value;closeModal();res(v)}); $('#v13SelectCancel').onclick=()=>{closeModal();res(null)};
  });
}
async function __v13ChooseCategory(title='Выберите категорию') {
  const cats=__v13Categories();
  const selected=await __v13Select(title,[...cats.map(c=>({value:c,label:c})),{value:'__new__',label:'+ Новая категория'}]);
  if(selected==='__new__'){const name=await ask('Название новой категории');return name&&name.trim()?name.trim():null} return selected;
}
async function __v13ChooseLocation(title, exclude='') {
  const rows=(S.locations||[]).filter(x=>x.active!==false && x.id!==exclude).map(x=>({value:x.id,label:x.name,sub:x.is_primary?'Основное место':''}));
  return rows.length ? __v13Select(title,rows) : null;
}
async function __v13CollectOperationLines(title) {
  const lines=[];
  while(true){
    const p=await chooseProduct(lines.length?`${title}: добавить ещё позицию`:title); if(!p) break;
    const q=await quantityFor(p,title); if(!q) break;
    const existing=lines.find(x=>x.product_key===q.product_key); if(existing) existing.quantity_base+=q.quantity_base; else lines.push(q);
    const more=await confirmBox(title,`Добавлено позиций: ${lines.length}. Добавить ещё товар?`); if(!more) break;
  }
  return lines;
}
async function __v13ScanCodeRaw() {
  if(typeof Html5Qrcode==='undefined'){toast('Модуль камеры ещё не загружен. Используйте ручной ввод.',true);return null}
  return new Promise(async resolve=>{
    openModal(`<h2>Сканирование</h2><div id="v13reader" style="width:100%;min-height:260px;border-radius:14px;overflow:hidden"></div><p class="muted">Наведите камеру на QR-код или штрихкод.</p><button id="v13ScanCancel" class="secondary" style="width:100%">Закрыть</button>`);
    const qr=new Html5Qrcode('v13reader');let done=false;
    const stop=async()=>{try{await qr.stop()}catch(_){}try{qr.clear()}catch(_){}};
    $('#v13ScanCancel').onclick=async()=>{done=true;await stop();closeModal();resolve(null)};
    try{await qr.start({facingMode:'environment'},{fps:10,qrbox:{width:250,height:160}},async decoded=>{if(done)return;done=true;await stop();closeModal();resolve(decoded)},()=>{})}catch(e){await stop();closeModal();toast('Не удалось открыть камеру: '+e,true);resolve(null)}
  });
}

// ---------- Delivery: code scanner + category-aware product selection ----------
const __v13PrevRenderDelivery = renderDelivery;
const __v13PrevWireDelivery = wireDelivery;
renderDelivery = function(){
  let html=__v13PrevRenderDelivery();
