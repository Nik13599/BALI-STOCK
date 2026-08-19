(function () {
  'use strict';
  window.__BALI_STOCK_V15_DELIVERY_LINK__ = '15.0';

  var KEY_V15 = typeof KEY !== 'undefined' ? KEY : 'sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29';
  var REST = 'https://mvnxfouyoynqyjdpcblh.supabase.co/rest/v1/';
  var requestCache = [];
  var loading = false;

  function clean(v) { return String(v == null ? '' : v).trim(); }
  function keyFor(p) { return keyOf(p); }
  function productForKey(k) { return (S.products || []).find(function (p) { return keyFor(p) === k; }) || null; }
  function supplierName(id) { var s = (S.suppliers || []).find(function (x) { return x.id === id; }); return s ? s.name : 'Поставщик'; }
  function requestOpen(r) { return ['confirmed', 'sent', 'partial'].indexOf(r.status) >= 0; }
  function requestNumber(r) {
    var d = new Date(r.created_at), suffix = clean(r.id).replace(/-/g, '').slice(0, 4).toUpperCase();
    return 'ЗАК-' + d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + String(d.getDate()).padStart(2, '0') + '-' + suffix;
  }

  async function loadRequests() {
    if (loading) return requestCache;
    loading = true;
    try {
      var headers = {apikey: KEY_V15, Accept: 'application/json'};
      var responses = await Promise.all([
        fetch(REST + 'stock_purchase_requests?select=id,supplier_id,status,created_at&order=created_at.desc&limit=100', {headers: headers, cache: 'no-store'}),
        fetch(REST + 'stock_purchase_request_lines?select=id,request_id,product_key,requested_quantity,received_quantity,unit_cost&order=id.asc', {headers: headers, cache: 'no-store'})
      ]);
      if (!responses[0].ok || !responses[1].ok) throw new Error('HTTP ' + responses[0].status + '/' + responses[1].status);
      var requests = await responses[0].json(), lines = await responses[1].json(), byRequest = {};
      lines.forEach(function (line) { (byRequest[line.request_id] || (byRequest[line.request_id] = [])).push(line); });
      requestCache = requests.map(function (r) { r.lines = byRequest[r.id] || []; return r; }).filter(requestOpen);
      return requestCache;
    } catch (e) {
      console.warn('BALI V15 purchase request load failed', e);
      return requestCache;
    } finally {
      loading = false;
    }
  }

  function prefillRequest(request) {
    if (!request) return;
    var lines = [];
    (request.lines || []).forEach(function (line) {
      var outstanding = Math.max(0, Number(line.requested_quantity || 0) - Number(line.received_quantity || 0));
      if (!outstanding) return;
      var p = productForKey(line.product_key);
      if (!p) return;
      var size = Math.max(1, Number(p.package_size || 1));
      var whole = p.stock_unit === 'pcs' ? outstanding : Math.floor(outstanding / size);
      var extra = p.stock_unit === 'pcs' ? 0 : outstanding % size;
      lines.push({
        product_key: line.product_key,
        whole: whole,
        extra: extra,
        cost: line.unit_cost == null ? null : Number(line.unit_cost),
        corrected: true,
        source: 'Заявка ' + requestNumber(request)
      });
    });
    delivery.lines = lines;
    delivery.__v15RequestId = request.id;
    delivery.__v15SupplierId = request.supplier_id || '';
    render();
  }

  var baseApi = api;
  api = async function (action, body, needPin) {
    var payload = body || {};
    if (action === 'delivery' && delivery && delivery.__v15RequestId) {
      payload = Object.assign({}, payload, {
        metadata: Object.assign({}, payload.metadata || {}, {purchase_request_id: delivery.__v15RequestId})
      });
    }
    return baseApi(action, payload, needPin);
  };

  async function enhanceRequestSelector() {
    if (tab !== 'delivery') return;
    var supplier = document.getElementById('delSup');
    if (!supplier || document.getElementById('v15RequestWrap')) return;
    var requests = await loadRequests();
    if (tab !== 'delivery' || !document.getElementById('delSup')) return;
    if (!requests.length) return;

    var wrap = document.createElement('div');
    wrap.id = 'v15RequestWrap';
    wrap.style.marginTop = '9px';
    wrap.innerHTML = '<div class="muted" style="margin-bottom:4px;font-weight:800">Заявка на закупку — при наличии</div>' +
      '<select id="v15RequestSelect" class="input"><option value="">Без привязки к заявке</option>' +
      requests.map(function (r) {
        return '<option value="' + esc(r.id) + '" ' + (delivery.__v15RequestId === r.id ? 'selected' : '') + '>' + esc(requestNumber(r) + ' • ' + supplierName(r.supplier_id)) + '</option>';
      }).join('') + '</select>';

    var supplierWrap = document.getElementById('v15SupWrap');
    var anchor = supplierWrap || supplier;
    if (anchor.parentNode) anchor.parentNode.insertBefore(wrap, anchor.nextSibling);

    document.getElementById('v15RequestSelect').onchange = function (e) {
      var id = clean(e.target.value);
      if (!id) {
        delivery.__v15RequestId = '';
        return;
      }
      var request = requests.find(function (r) { return r.id === id; });
      if (request) prefillRequest(request);
    };
  }

  var previousRender = render;
  render = function () {
    previousRender();
    if (tab === 'delivery') setTimeout(enhanceRequestSelector, 0);
  };

  window.addEventListener('focus', function () {
    if (tab === 'delivery') {
      requestCache = [];
      setTimeout(enhanceRequestSelector, 0);
    }
  });

  if (tab === 'delivery') setTimeout(enhanceRequestSelector, 80);
})();
