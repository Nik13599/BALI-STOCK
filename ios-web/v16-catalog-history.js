(function () {
  'use strict';
  window.__BALI_STOCK_V16_CATALOG_HISTORY__ = '16.1';

  var CATALOG_API = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-catalog-api';
  var previousRender = render;

  function clean(v) { return String(v == null ? '' : v).trim(); }
  function lower(v) { return clean(v).toLowerCase(); }
  function h(v) { return typeof esc === 'function' ? esc(v) : clean(v).replace(/[&<>"']/g, function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];}); }
  function productKey(p) { return keyOf(p); }
  function categories() {
    var seen = {}, result = [];
    (S.products || []).filter(function(p){return p.active !== false;}).forEach(function(p){
      var name = clean(p.category_name);
      if (!name || seen[name]) return;
      seen[name] = true;
      result.push({name:name, sort:Number(p.category_sort == null ? 999999 : p.category_sort)});
    });
    return result.sort(function(a,b){return a.sort-b.sort || a.name.localeCompare(b.name,'ru');});
  }
  function productSort(a,b) {
    var ca = Number(a.category_sort == null ? 999999 : a.category_sort), cb = Number(b.category_sort == null ? 999999 : b.category_sort);
    if (ca !== cb) return ca-cb;
    var c = String(a.category_name || '').localeCompare(String(b.category_name || ''),'ru');
    return c || String(a.name || '').localeCompare(String(b.name || ''),'ru');
  }
  async function catalogRequest(body) {
    var response = await fetch(CATALOG_API, {
      method:'POST',
      headers:{apikey:KEY,Accept:'application/json','Content-Type':'application/json'},
      body:JSON.stringify(body)
    });
    var data = await response.json().catch(function(){return {};});
    if (!response.ok) throw Error(data.error || ('HTTP '+response.status));
    return data;
  }
  function catalogPost(employee, items) {
    return catalogRequest({action:'catalog_product_batch',employee:clean(employee),items:items});
  }
  function catalogDelete(employee, product) {
    return catalogRequest({action:'product_delete',employee:clean(employee),product_key:productKey(product)});
  }

  function payloadFromProduct(p, values) {
    return {
      old_product_key: p ? productKey(p) : null,
      name: clean(values.name),
      category_name: clean(values.category),
      category_sort: Number(values.categorySort || 0),
      package_size: Number(values.packageSize || 1),
      stock_unit: values.stockUnit || 'ml',
      minimum_amount: Number(values.minimum || 0),
      target_amount: Number(values.target || 0),
      barcode: clean(values.barcode) || null,
      variance_recheck_amount: Number(values.variance || 0),
      active: true,
      sell_by_bottle: p ? p.sell_by_bottle === true : false,
      bottle_sale_price: p ? p.bottle_sale_price : null,
      portion_sale: p ? p.portion_sale === true : false,
      portion_prices: p && Array.isArray(p.portion_prices) ? p.portion_prices : [],
      image_path: p ? (p.image_path || null) : null
    };
  }

  async function deleteProduct(product) {
    if (init(product) && qty(product) !== 0) {
      toast('Нельзя удалить товар с ненулевым остатком. Сначала проведите переучёт и установите остаток 0.', true);
      return;
    }
    var ok = await confirmBox(
      'Удалить товар?',
      '«'+clean(product.name)+'» исчезнет из текущего склада, поиска, поставок, закупок и новых переучётов. Проведённая история операций сохранится. Восстановление кнопкой отмены невозможно.'
    );
    if (!ok) return;
    var employee = await ask('Кто удаляет товар?');
    if (!employee) return;
    try {
      await catalogDelete(employee, product);
      await snapshot();
      toast('Товар удалён. История операций сохранена.');
      openCatalogManager();
    } catch(e) {
      toast(String(e&&e.message?e.message:e), true);
    }
  }

  function openCatalogManager() {
    var items = (S.products || []).filter(function(p){return p.active !== false;}).sort(productSort);
    openModal('<h2>Редактирование склада</h2>'+
      '<div class="muted">Пароль не требуется. Можно добавлять, менять и удалять товары. Удаление разрешено только при нулевом остатке; проведённая история сохраняется. Закупочная цена меняется только фактической поставкой.</div>'+
      '<button id="v16AddProduct" style="width:100%;margin-top:12px">+ ДОБАВИТЬ НОВЫЙ ТОВАР</button>'+
      '<input id="v16CatalogSearch" class="input" style="margin-top:10px" placeholder="Поиск товара, категории или кода">'+
      '<div id="v16CatalogList" style="margin-top:10px"></div>'+
      '<button id="v16CatalogClose" class="secondary" style="width:100%;margin-top:8px">Закрыть</button>');

    function draw() {
      var q = lower(document.getElementById('v16CatalogSearch').value);
      var filtered = items.filter(function(p){return !q || lower(p.name+' '+p.category_name+' '+(p.barcode||'')).indexOf(q)>=0;});
      var box = document.getElementById('v16CatalogList');
      box.innerHTML = filtered.slice(0,220).map(function(p){
        var key=h(productKey(p));
        return '<div class="card" style="margin:7px 0"><div class="name">'+h(p.name)+'</div><div class="muted" style="color:#39ff6a">'+h(p.category_name)+'</div><div class="muted">'+h(p.stock_unit==='pcs'?'1 шт.':p.package_size+' '+(p.stock_unit==='g'?'г':'мл'))+' • код '+h(p.barcode||'—')+'</div><div class="toolbar" style="margin-top:8px"><button class="secondary v16EditProduct" data-key="'+key+'">Настроить</button><button class="secondary v16DeleteProduct" data-key="'+key+'">Удалить товар</button></div></div>';
      }).join('') || '<div class="card">Ничего не найдено.</div>';
      box.querySelectorAll('.v16EditProduct').forEach(function(b){b.onclick=function(){var p=(S.products||[]).find(function(x){return productKey(x)===b.dataset.key;});if(p)openProductEditor(p);};});
      box.querySelectorAll('.v16DeleteProduct').forEach(function(b){b.onclick=function(){var p=(S.products||[]).find(function(x){return productKey(x)===b.dataset.key;});if(p)deleteProduct(p);};});
    }
    document.getElementById('v16CatalogSearch').oninput = draw;
    document.getElementById('v16AddProduct').onclick = function(){openProductEditor(null);};
    document.getElementById('v16CatalogClose').onclick = closeModal;
    draw();
  }

  function openProductEditor(product) {
    var cats = categories();
    if (!cats.length) { toast('Нет доступных категорий.',true); return; }
    var category = product ? product.category_name : cats[0].name;
    var categorySort = product ? Number(product.category_sort || 0) : cats[0].sort;
    var stockUnit = product ? product.stock_unit : 'ml';
    var packageSize = product ? Number(product.package_size || 1) : 750;
    openModal('<h2>'+(product?'Редактировать товар':'Добавить новый товар')+'</h2>'+
      '<input id="v16Name" class="input" placeholder="Название товара *" value="'+h(product?product.name:'')+'">'+
      '<select id="v16Category" class="input" style="margin-top:8px">'+cats.map(function(c){return '<option value="'+h(c.name)+'" data-sort="'+c.sort+'" '+(c.name===category?'selected':'')+'>'+h(c.name)+'</option>';}).join('')+'</select>'+
      '<div class="grid2" style="margin-top:8px"><select id="v16Unit" class="input"><option value="ml" '+(stockUnit==='ml'?'selected':'')+'>мл</option><option value="g" '+(stockUnit==='g'?'selected':'')+'>г</option><option value="pcs" '+(stockUnit==='pcs'?'selected':'')+'>шт.</option></select><input id="v16Package" class="input" inputmode="numeric" placeholder="Размер упаковки" value="'+h(packageSize)+'"></div>'+
      '<input id="v16Barcode" class="input" style="margin-top:8px" placeholder="Штрихкод / код товара" value="'+h(product&&product.barcode?product.barcode:'')+'">'+
      '<div class="grid2" style="margin-top:8px"><input id="v16Minimum" class="input" inputmode="numeric" placeholder="Минимум" value="'+h(product?Number(product.minimum_amount||0):0)+'"><input id="v16Target" class="input" inputmode="numeric" placeholder="Целевой остаток" value="'+h(product?Number(product.target_amount||0):0)+'"></div>'+
      '<input id="v16Variance" class="input" style="margin-top:8px" inputmode="numeric" placeholder="Порог перепроверки" value="'+h(product?Number(product.variance_recheck_amount||0):0)+'">'+
      (!product?'<div class="card" style="margin-top:10px"><div class="muted">Новый товар создаётся с остатком «не введён». Поставщика, фото, продажи и цены можно настроить затем в карточке товара через ⚙.</div></div>':'')+
      '<div class="toolbar" style="margin-top:12px"><button id="v16SaveProduct">'+(product?'СОХРАНИТЬ':'ДОБАВИТЬ ТОВАР')+'</button><button id="v16EditorCancel" class="secondary">Отмена</button></div>');

    function syncPackageState() {
      var unit = document.getElementById('v16Unit').value, field = document.getElementById('v16Package');
      if (unit === 'pcs') { field.value='1'; field.disabled=true; } else field.disabled=false;
    }
    document.getElementById('v16Unit').onchange = syncPackageState;
    document.getElementById('v16EditorCancel').onclick = openCatalogManager;
    document.getElementById('v16SaveProduct').onclick = async function(){
      var name = clean(document.getElementById('v16Name').value);
      var catSelect = document.getElementById('v16Category');
      var cat = clean(catSelect.value);
      var opt = catSelect.options[catSelect.selectedIndex];
      categorySort = Number(opt && opt.dataset.sort || categorySort || 0);
      var unit = document.getElementById('v16Unit').value;
      var pack = unit==='pcs'?1:parseInt(document.getElementById('v16Package').value||'0',10);
      var minimum = parseInt(document.getElementById('v16Minimum').value||'0',10);
      var target = parseInt(document.getElementById('v16Target').value||'0',10);
      var variance = parseInt(document.getElementById('v16Variance').value||'0',10);
      if (!name || !cat || !Number.isFinite(pack) || pack<=0 || minimum<0 || target<0 || variance<0) { toast('Проверьте название, категорию, упаковку, минимум и цель.',true); return; }
      if (!product) {
        var duplicate=(S.products||[]).some(function(p){return p.active!==false&&lower(p.name)===lower(name)&&p.stock_unit===unit&&Number(p.package_size)===pack;});
        if (duplicate) { toast('Такая позиция уже существует.',true); return; }
      }
      var employee = await ask(product?'Кто подтверждает изменения?':'Кто добавляет новый товар?');
      if (!employee) return;
      var values={name:name,category:cat,categorySort:categorySort,stockUnit:unit,packageSize:pack,barcode:document.getElementById('v16Barcode').value,minimum:minimum,target:target,variance:variance};
      try {
        await catalogPost(employee,[payloadFromProduct(product,values)]);
        await snapshot();
        toast(product?'Товар сохранён':'Новый товар добавлен');
        openCatalogManager();
      } catch(e) { toast(String(e&&e.message?e.message:e),true); }
    };
    syncPackageState();
  }

  function enhanceStock() {
    if (document.getElementById('v16CatalogEdit')) return;
    var section = document.querySelector('#app .section') || document.getElementById('app');
    if (!section) return;
    var toolbar = section.querySelector('.toolbar');
    if (!toolbar) return;
    var button = document.createElement('button');
    button.id='v16CatalogEdit';
    button.className='secondary';
    button.textContent='✎ Редактировать';
    button.onclick=openCatalogManager;
    toolbar.appendChild(button);
  }

  function draftKey(d) { return clean(d.employee_name)+'|'+clean(d.started_at); }
  function enhanceDraftHistory() {
    var drafts=(S.drafts||[]).filter(function(d){return clean(d.status)!=='completed';});
    var old=document.getElementById('v16DraftHistory');
    if (!drafts.length) { if(old)old.remove(); return; }
    if (old) return;
    var app=document.getElementById('app');
    if(!app)return;
    var box=document.createElement('div');
    box.id='v16DraftHistory';
    box.className='card';
    box.style.marginBottom='12px';
    box.innerHTML='<div class="name">Черновики переучёта</div><div class="muted" style="margin:5px 0 9px">Удалять можно только черновики. Проведённые операции не удаляются.</div>'+drafts.map(function(d){return '<div class="card" style="margin:7px 0"><div class="row"><div class="grow"><b>'+h(d.employee_name||'Без ФИО')+'</b><div class="muted">'+h(d.status||'draft')+' • заполнено '+h(d.filled_count||0)+' / '+h(d.total_count||0)+'</div></div><button class="danger v16DeleteDraft" data-key="'+h(draftKey(d))+'">Удалить</button></div></div>';}).join('');
    var section=app.querySelector('.section');
    if(section)section.insertBefore(box,section.firstChild);else app.insertBefore(box,app.firstChild);
    box.querySelectorAll('.v16DeleteDraft').forEach(function(b){b.onclick=async function(){var d=drafts.find(function(x){return draftKey(x)===b.dataset.key;});if(!d)return;var ok=await confirmBox('Удалить черновик?','Черновик будет удалён без возможности восстановления. Завершённые операции останутся в истории.');if(!ok)return;try{await api('draft_delete',{employee:d.employee_name||''},true);await snapshot();render();toast('Черновик удалён');}catch(e){toast(String(e&&e.message?e.message:e),true);}};});
  }

  function enhance() {
    if (tab==='stock') enhanceStock();
    if (tab==='control') enhanceDraftHistory();
  }

  render=function(){previousRender();setTimeout(enhance,0);};
  setTimeout(enhance,80);
})();