(function(){
  'use strict';
  window.__BALI_V14_SCAN_WORKFLOWS__='v14.5';

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
  function chooseUnknownAction(code){
    return new Promise(function(resolve){
      openModal('<h2>Код не найден</h2><p class="muted">Код '+esc(clean(code))+' не привязан ни к одному товару.</p><button id="v14AssignUnknown" style="width:100%">Назначить код товару</button><button id="v14FindUnknown" class="secondary" style="width:100%;margin-top:8px">Найти товар вручную</button><button id="v14CancelUnknown" class="secondary" style="width:100%;margin-top:8px">Закрыть</button>');
      document.getElementById('v14AssignUnknown').onclick=function(){closeModal();resolve('assign')};
      document.getElementById('v14FindUnknown').onclick=function(){closeModal();resolve('manual')};
      document.getElementById('v14CancelUnknown').onclick=function(){closeModal();resolve(null)};
    });
  }
  async function resolveProductCode(code){
    var known=byCode(code);if(known)return known;
    var action=await chooseUnknownAction(code);if(!action)return null;
    var selected=await chooseProduct(action==='assign'?'Выберите товар для назначения кода':'Найдите товар вручную');
    if(!selected||action==='manual')return selected||null;
    var employee=await ask('ФИО сотрудника');if(!employee)return null;
    try{
      await api('product_meta',{
        employee:employee,
        product_key:keyOf(selected),
        minimum_amount:n(selected.minimum_amount),
        target_amount:n(selected.target_amount),
        barcode:clean(code),
        variance_recheck_amount:n(selected.variance_recheck_amount)
      },true);
      await snapshot().catch(function(){});
      toast(navigator.onLine?'Код назначен товару':'Код сохранён на iPhone и будет синхронизирован');
      return byCode(code)||selected;
    }catch(e){
      toast('Не удалось назначить код: '+String(e&&e.message?e.message:e),true);
      return null;
    }
  }
  window.__baliResolveProductCode=resolveProductCode;
  window.handleProductCode=async function(code){var p=await resolveProductCode(code);if(p&&window.v14ShowProduct)window.v14ShowProduct(p)};

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
  async function handleCountCode(code,nextScan){var p=await resolveProductCode(code);if(!p){if(nextScan)setTimeout(countScanFlow,80);return}var line=countLineForProduct(p);if(!line){toast('Товар '+p.name+' не входит в текущий переучёт.',true);if(nextScan)setTimeout(countScanFlow,80);return}await editCountLine(line,nextScan)}
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
  async function handleDeliveryCode(code,nextScan){var p=await resolveProductCode(code);if(!p){if(nextScan)setTimeout(deliveryScanFlow,80);return}await editDeliveryProduct(p,nextScan)}
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
