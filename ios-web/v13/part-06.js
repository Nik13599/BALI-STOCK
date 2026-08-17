  return `<h2>Контроль</h2><div class="toolbar noPrint"><button id="writeoff">Списать</button><button id="transfer" class="secondary">Переместить</button><button id="v13AddProduct" class="secondary">+ Товар</button><button id="v13EditProduct" class="secondary">Редактировать товар</button><button id="v13RenameCat" class="secondary">Категории</button></div><div class="v13-kpi"><div class="metric"><span class="muted">Стоимость склада</span><b>${__v13FmtValue(value.total)}</b><small class="muted">без цены: ${value.missing}${value.foreign?` • другая валюта: ${value.foreign}`:''}</small></div><div class="metric"><span class="muted">Критический остаток</span><b>${low}</b></div><div class="metric"><span class="muted">Не пересчитано</span><b>${uninit}</b></div><div class="metric"><span class="muted">Среднее время переучёта</span><b>${dur(a.average_stocktake_seconds)}</b></div></div><div class="v13-section-title">Поставщики</div><div class="toolbar noPrint"><button id="newSupplier" class="secondary">+ Поставщик</button><button id="v13LinkSupplier" class="secondary">Привязать к товару</button></div>${(S.suppliers||[]).filter(x=>x.active!==false).map(s=>`<div class="card"><div class="row"><div class="grow"><div class="name">${esc(s.name)}</div><div class="muted">${esc([s.contact_person,s.phone,s.email].filter(Boolean).join(' • '))}</div>${s.notes?`<div class="muted">${esc(s.notes)}</div>`:''}</div><button class="secondary v13EditSupplier" data-id="${esc(s.id)}">Изменить</button></div></div>`).join('')||'<div class="muted">Поставщиков нет.</div>'}<div class="v13-section-title">Места хранения</div><div class="toolbar noPrint"><button id="newLoc" class="secondary">+ Место</button></div>${(S.locations||[]).filter(x=>x.active!==false).map(l=>`<div class="card"><div class="row"><div class="grow"><b>${esc(l.name)}</b> ${l.is_primary?'<span class="pill">основной</span>':''}</div><button class="secondary v13LocOpen" data-id="${esc(l.id)}">Остатки</button><button class="secondary v13LocEdit" data-id="${esc(l.id)}">Изменить</button></div></div>`).join('')||'<div class="muted">Мест хранения нет.</div>'}<div class="v13-section-title">Параметры товара</div><div class="card"><select id="ctlProd" class="input">${active.map(p=>`<option value="${esc(keyOf(p))}">${esc(p.category_name+' — '+p.name)}</option>`).join('')}</select><div class="v13-actions"><button id="editProd">Минимум / цель / цена / код</button><button id="v13ProdSup" class="secondary">Поставщики товара</button></div></div><div class="v13-section-title">Расхождения последних переучётов</div>${variances.slice(0,25).map(x=>`<div class="card"><div class="name">${esc(x.l.product_name)}</div><div class="muted">${dt(x.o.created_at)} • ${esc(x.o.employee_name||'')}</div><div class="amount ${x.d<0?'v13-delta-neg':'v13-delta-pos'}">Расчётно ${n(x.l.before_quantity)} → фактически ${n(x.l.after_quantity)} • ${x.d>0?'+':''}${x.d} ${esc(x.l.stock_unit)}</div></div>`).join('')||'<div class="muted">Расхождений пока нет.</div>'}<div class="v13-section-title">Синхронизация</div><div class="card"><div class="name" id="v13SyncSummary">Статус отображается в верхней панели</div><div class="muted">Операции сначала сохраняются локально и отправляются в общую базу при наличии сети.</div><button id="v13Flush" class="secondary" style="margin-top:8px">Синхронизировать сейчас</button></div>`;
};
function __v13ShowProductSuppliers(p){const links=(S.product_suppliers||[]).filter(x=>x.product_key===keyOf(p)&&x.active!==false);openModal(`<h2>${esc(p.name)}</h2><p class="muted">Поставщики товара</p>${links.map(l=>{const s=(S.suppliers||[]).find(x=>x.id===l.supplier_id);return `<div class="card"><div class="name">${esc(s?.name||'Поставщик')}</div><div class="muted">${l.is_primary?'Основной • ':''}${l.supplier_sku?`SKU ${esc(l.supplier_sku)} • `:''}${l.last_price!=null?`${money(l.last_price,l.currency)}`:''}</div></div>`}).join('')||'<div class="muted">Поставщики не привязаны.</div>'}<button onclick="closeModal()" class="secondary" style="width:100%">Закрыть</button>`)}
wireControl=function(){
  $('#writeoff').onclick=writeoff;$('#transfer').onclick=transfer;$('#v13AddProduct').onclick=__v13AddProduct;$('#v13EditProduct').onclick=__v13EditProduct;$('#v13RenameCat').onclick=__v13RenameCategory;$('#newSupplier').onclick=()=>__v13SupplierForm();$('#v13LinkSupplier').onclick=__v13LinkSupplier;$('#newLoc').onclick=()=>__v13LocationForm();$('#editProd').onclick=editProductControl;$('#v13ProdSup').onclick=()=>{const p=S.products.find(x=>keyOf(x)===$('#ctlProd').value);if(p)__v13ShowProductSuppliers(p)};document.querySelectorAll('.v13EditSupplier').forEach(b=>b.onclick=()=>{const s=S.suppliers.find(x=>x.id===b.dataset.id);if(s)__v13SupplierForm(s)});document.querySelectorAll('.v13LocOpen').forEach(b=>b.onclick=()=>{const l=S.locations.find(x=>x.id===b.dataset.id);if(l)__v13LocationDetails(l)});document.querySelectorAll('.v13LocEdit').forEach(b=>b.onclick=()=>{const l=S.locations.find(x=>x.id===b.dataset.id);if(l)__v13LocationForm(l)});$('#v13Flush').onclick=()=>__v12Flush(true);
};



// ---------- Cross-device stocktake draft compatibility ----------
function __v13NormalizeDraftLine(l) {
  const out = {...l};
  if (out.whole == null && out.whole_packages != null) out.whole = out.whole_packages;
  if (out.extra == null && out.extra_amount != null) out.extra = out.extra_amount;
  if (out.whole_packages == null && out.whole != null) out.whole_packages = out.whole;
  if (out.extra_amount == null && out.extra != null) out.extra_amount = out.extra;
  if (!out.product_key && out.product_name) out.product_key = findProductKey(out.product_name, out.stock_unit, out.package_size);
  out.comment = out.comment || '';
  out.rechecked = !!out.rechecked;
  return out;
}
function __v13NormalizeRemoteDrafts() {
  S.drafts = (S.drafts || []).map(d => {
    const payload = {...(d.payload || {})};
    payload.lines = (payload.lines || []).map(__v13NormalizeDraftLine);
    return {...d, payload};
  });
}
const __v13PrevStartCount = startCount;
startCount = async function() { __v13NormalizeRemoteDrafts(); return __v13PrevStartCount(); };
saveCount = function(remote=true) {
  if(!count)return;
  count.lines = (count.lines || []).map(__v13NormalizeDraftLine);
  localStorage.setItem('bali_count_'+count.employee.toLowerCase(), JSON.stringify(count));
  clearTimeout(countSyncTimer);
