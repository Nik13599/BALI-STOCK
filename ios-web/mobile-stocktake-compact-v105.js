(function () {
  'use strict';
  window.__BALI_STOCK_MOBILE_STOCKTAKE_COMPACT__ = '1.0.5';

  var legacyRenderCount = renderCount;
  var legacyWireCount = wireCount;
  var legacyHandleProductCode = window.handleProductCode;

  function mobileCount() {
    return window.matchMedia('(max-width:760px)').matches || /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  }

  function ensureMobileStocktakeCss() {
    if (document.getElementById('baliMobileStocktakeCss')) return;
    var style = document.createElement('style');
    style.id = 'baliMobileStocktakeCss';
    style.textContent = '@media(max-width:760px){.baliCountHead{display:flex;align-items:center;gap:7px;margin-bottom:4px}.baliCountHead h2{font-size:17px;margin:0;line-height:1.05}.baliCountMeta{font-size:11px;color:#9fb3a5}.baliCountRestart{padding:6px 8px;font-size:11px;margin-left:auto}.baliCountProgress{height:5px!important;margin:6px 0 7px!important}.baliCountTools{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:7px;align-items:center;margin-bottom:5px}.baliCountTools .input{margin:0!important;min-height:38px;padding:8px 10px!important}.baliCountScan{height:38px;padding:7px 10px!important;white-space:nowrap;font-size:12px}.baliCountFilter{display:flex;align-items:center;gap:6px;font-size:11px;margin:0 0 4px;color:#b7c5bb}.baliCountFilter input{margin:0}.baliCountStats{font-size:11px;color:#9fb3a5;margin-left:auto}.cat{margin-top:9px!important}}';
    document.head.appendChild(style);
  }

  function renderCompactCount() {
    if (!mobileCount() || !count) return legacyRenderCount();
    ensureMobileStocktakeCss();
    var filled = count.lines.filter(filledCountLine).length;
    var total = count.lines.length;
    var q = count.search || '';
    var lines = count.lines.filter(function (l) {
      return (!count.onlyUnfilled || !filledCountLine(l)) && (!q || ((l.product_name + ' ' + l.category_name).toLowerCase().includes(q.toLowerCase())));
    });
    var groups = {};
    lines.forEach(function (l) { (groups[l.category_name] ??= []).push(l); });
    return '<div class="baliCountHead"><div class="grow"><h2>Переучёт • ' + esc(count.employee) + '</h2><div class="baliCountMeta">' + dur(count.active_seconds) + ' • ' + filled + '/' + total + '</div></div><button id="cntRestart" class="danger baliCountRestart">Сначала</button></div>' +
      '<div class="progress baliCountProgress"><i style="width:' + (total ? filled / total * 100 : 0) + '%"></i></div>' +
      '<div class="baliCountTools"><input id="cntSearch" class="input grow" placeholder="Поиск" value="' + esc(q) + '"><button id="cntScan" class="baliCountScan">▣ Скан</button></div>' +
      '<label class="baliCountFilter"><input id="onlyUnfilled" type="checkbox" ' + (count.onlyUnfilled ? 'checked' : '') + '> Не заполнено <span class="baliCountStats">осталось ' + (total - filled) + '</span></label>' +
      '<div>' + Object.entries(groups).map(function (entry) {
        var cat = entry[0], ls = entry[1];
        return '<div class="cat"><span>' + esc(cat) + '</span><small>' + ls.filter(filledCountLine).length + '/' + ls.length + '</small></div>' + ls.map(countLineHtml).join('');
      }).join('') + '</div>' +
      '<div class="card"><b>Прогресс: ' + filled + ' из ' + total + '</b><button id="cntFinish" ' + (filled === total ? '' : 'disabled') + ' style="width:100%;margin-top:8px">ЗАВЕРШИТЬ ПЕРЕУЧЁТ</button></div>';
  }

  function wireCompactCount() {
    if (!mobileCount() || !count) return legacyWireCount();
    var search = document.getElementById('cntSearch');
    if (search) search.oninput = function (e) { count.search = e.target.value; render(); };
    var only = document.getElementById('onlyUnfilled');
    if (only) only.onchange = function (e) { count.onlyUnfilled = e.target.checked; render(); };
    document.querySelectorAll('.cw').forEach(function (x) { x.oninput = function () { var l = count.lines.find(function (y) { return y.product_key === x.dataset.key; }); l.whole = x.value; l.rechecked = false; saveCount(); render(); }; });
    document.querySelectorAll('.ce').forEach(function (x) { x.oninput = function () { var l = count.lines.find(function (y) { return y.product_key === x.dataset.key; }); l.extra = x.value; l.rechecked = false; saveCount(); render(); }; });
    document.querySelectorAll('.cc').forEach(function (x) { x.oninput = function () { var l = count.lines.find(function (y) { return y.product_key === x.dataset.key; }); l.comment = x.value; saveCount(); }; });
    var restart = document.getElementById('cntRestart');
    if (restart) restart.onclick = async function () { if (await confirmBox('Начать заново?', 'Все данные текущего черновика будут удалены.')) { await api('draft_delete', { employee: count.employee, started_at: count.started_at || '' }, true); localStorage.removeItem('bali_count_' + count.employee.toLowerCase()); clearInterval(countTimer); count = null; render(); } };
    var finish = document.getElementById('cntFinish');
    if (finish) finish.onclick = finishCount;
    var scan = document.getElementById('cntScan');
    if (scan) scan.onclick = function () { window.__baliCountScan = true; setTimeout(function () { window.__baliCountScan = false; }, 30000); startProductCodeScanner(); };
  }

  window.handleProductCode = async function (code) {
    if (!window.__baliCountScan || !count) return legacyHandleProductCode(code);
    window.__baliCountScan = false;
    var p = window.v14ProductByCode(code);
    if (!p) { toast('Код ' + String(code || '').trim() + ' не привязан к товару.', true); return; }
    var l = count.lines.find(function (x) { return x.product_key === keyOf(p); });
    if (!l) { toast('Товар не входит в текущий переучёт.', true); return; }
    var whole = await ask(p.name + ' • ' + (l.stock_unit === 'pcs' ? 'Фактически, шт.' : packLabel(p)), 'number', l.whole == null ? '' : String(l.whole));
    if (whole == null) return;
    var w = Number(whole);
    if (!Number.isInteger(w) || w < 0) { toast('Проверьте количество', true); return; }
    var extra = 0;
    if (l.stock_unit !== 'pcs') {
      var value = await ask('Доп. ' + unit(p), 'number', l.extra == null ? '' : String(l.extra));
      if (value == null) return;
      extra = Number(value);
      if (!Number.isInteger(extra) || extra < 0 || extra >= Number(l.package_size)) { toast('Дополнительный остаток: 0–' + (Number(l.package_size) - 1), true); return; }
    }
    l.whole = w;
    l.extra = extra;
    l.rechecked = false;
    saveCount();
    toast(p.name + ' сохранён');
    render();
  };

  renderCount = renderCompactCount;
  wireCount = wireCompactCount;
})();
