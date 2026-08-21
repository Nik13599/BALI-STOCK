(function () {
  'use strict';

  window.__BALI_STOCK_IOS_PERSISTENCE__ = '17.0';

  var SYNC_API = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-sync-api';
  var DB_NAME = 'bali-stock-ios-persistence';
  var DB_VERSION = 1;
  var LEGACY_QUEUE = 'bali-stock-v14-queue';
  var durableActions = new Set([
    'delivery', 'writeoff', 'transfer', 'correction', 'spot_stocktake', 'stocktake',
    'supplier_upsert', 'supplier_link', 'location_upsert', 'catalog_product_batch',
    'product_meta', 'product_meta_batch', 'product_image_upload',
    'purchase_request_create', 'purchase_request_status', 'draft_sync', 'draft_delete'
  ]);
  var originalApi = api;
  var originalSnapshot = snapshot;
  var flushing = false;
  var dbPromise = null;

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'ios-' + Date.now() + '-' + Math.random().toString(16).slice(2);
  }

  function openDb() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise(function (resolve, reject) {
      var request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = function () {
        var db = request.result;
        if (!db.objectStoreNames.contains('outbox')) db.createObjectStore('outbox', {keyPath: 'id'});
        if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv');
      };
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error); };
    });
    return dbPromise;
  }

  async function allItems() {
    var db = await openDb();
    return new Promise(function (resolve, reject) {
      var request = db.transaction('outbox', 'readonly').objectStore('outbox').getAll();
      request.onsuccess = function () {
        resolve((request.result || []).sort(function (a, b) {
          return String(a.created_at).localeCompare(String(b.created_at));
        }));
      };
      request.onerror = function () { reject(request.error); };
    });
  }

  async function putItem(item) {
    var db = await openDb();
    return new Promise(function (resolve, reject) {
      var tx = db.transaction('outbox', 'readwrite');
      tx.objectStore('outbox').put(item);
      tx.oncomplete = function () { resolve(); };
      tx.onerror = function () { reject(tx.error); };
    });
  }

  async function deleteItem(id) {
    var db = await openDb();
    return new Promise(function (resolve, reject) {
      var tx = db.transaction('outbox', 'readwrite');
      tx.objectStore('outbox').delete(id);
      tx.oncomplete = function () { resolve(); };
      tx.onerror = function () { reject(tx.error); };
    });
  }

  async function kvGet(key) {
    var db = await openDb();
    return new Promise(function (resolve, reject) {
      var request = db.transaction('kv', 'readonly').objectStore('kv').get(key);
      request.onsuccess = function () { resolve(request.result == null ? null : request.result); };
      request.onerror = function () { reject(request.error); };
    });
  }

  async function kvPut(key, value) {
    var db = await openDb();
    return new Promise(function (resolve, reject) {
      var tx = db.transaction('kv', 'readwrite');
      if (value == null) tx.objectStore('kv').delete(key);
      else tx.objectStore('kv').put(value, key);
      tx.oncomplete = function () { resolve(); };
      tx.onerror = function () { reject(tx.error); };
    });
  }

  function draftIdentity(payload) {
    return String(payload.employee || payload.employee_name || '').trim().toLowerCase() + '|' + String(payload.started_at || '').trim();
  }

  function sameDraft(left, right) {
    var leftEmployee = String(left.employee || left.employee_name || '').trim().toLowerCase();
    var rightEmployee = String(right.employee || right.employee_name || '').trim().toLowerCase();
    var leftStart = String(left.started_at || '').trim();
    var rightStart = String(right.started_at || '').trim();
    return leftEmployee === rightEmployee && (!leftStart || !rightStart || leftStart === rightStart);
  }

  async function coalesce(payload) {
    var items = await allItems();
    for (var i = 0; i < items.length; i++) {
      var queued = items[i].payload || {};
      var same = false;
      if (payload.action === 'draft_sync' || payload.action === 'draft_delete') {
        same = (queued.action === 'draft_sync' || queued.action === 'draft_delete') &&
          sameDraft(queued, payload);
      } else if (payload.action === 'product_meta') {
        same = queued.action === 'product_meta' && queued.product_key === payload.product_key;
      }
      if (same) await deleteItem(items[i].id);
    }
  }

  async function enqueue(action, body) {
    var id = uuid();
    var payload = Object.assign({}, body || {}, {action: action, client_action_id: id});
    await coalesce(payload);
    await putItem({id: id, action: action, payload: payload, created_at: new Date().toISOString(), last_error: null});
    await updateStatus();
    return id;
  }

  function networkError(error) {
    var message = String(error && error.message ? error.message : error || '');
    return navigator.onLine === false || error instanceof TypeError ||
      /failed to fetch|load failed|network|offline|internet|timed out/i.test(message);
  }

  async function sendItem(item) {
    var payload = await resolvePendingReferences(item.payload);
    var response = await fetch(SYNC_API, {
      method: 'POST',
      headers: {apikey: KEY, Accept: 'application/json', 'Content-Type': 'application/json'},
      body: JSON.stringify(payload)
    });
    var data = await response.json().catch(function () { return {}; });
    if (!response.ok) {
      var error = new Error(data.error || ('HTTP ' + response.status));
      error.permanent = response.status >= 400 && response.status < 500 && response.status !== 409 && data.pending !== true;
      throw error;
    }
    var resolvedId = data.id || data.operation_id;
    if (resolvedId && !String(resolvedId).startsWith('pending:')) {
      await kvPut('resolved:' + item.id, String(resolvedId));
    }
    return data;
  }

  async function resolvePendingReferences(value) {
    if (typeof value === 'string' && value.startsWith('pending:') && !value.startsWith('pending://')) {
      var resolved = await kvGet('resolved:' + value.slice('pending:'.length));
      if (!resolved) throw new Error('Зависимое изменение ожидает синхронизации предыдущей записи');
      return resolved;
    }
    if (Array.isArray(value)) {
      var array = [];
      for (var i = 0; i < value.length; i++) array.push(await resolvePendingReferences(value[i]));
      return array;
    }
    if (value && typeof value === 'object') {
      var object = {};
      var keys = Object.keys(value);
      for (var j = 0; j < keys.length; j++) object[keys[j]] = await resolvePendingReferences(value[keys[j]]);
      return object;
    }
    return value;
  }

  async function flush(wantedId) {
    if (flushing || navigator.onLine === false) return null;
    flushing = true;
    var wanted = null;
    try {
      var items = await allItems();
      for (var i = 0; i < items.length; i++) {
        var item = items[i];
        try {
          var result = await sendItem(item);
          if (result && result.snapshot) S = result.snapshot;
          await deleteItem(item.id);
          if (item.id === wantedId) wanted = result;
        } catch (error) {
          item.last_error = String(error && error.message ? error.message : error);
          if (error.permanent) {
            await deleteItem(item.id);
            if (item.id === wantedId) throw error;
            continue;
          }
          await putItem(item);
          break;
        }
      }
      try { localStorage.setItem('bali-stock-v14-snapshot', JSON.stringify(S)); } catch (_) {}
      return wanted;
    } finally {
      flushing = false;
      await updateStatus();
    }
  }

  function productByKey(key) {
    return (S.products || []).find(function (product) { return keyOf(product) === key; });
  }

  function addPendingOperation(action, body, id, rows) {
    S.operations = S.operations || [];
    S.operations.unshift({
      id: 'pending:' + id,
      operation_id: 'pending:' + id,
      operation_type: action,
      employee_name: body.employee || null,
      created_at: new Date().toISOString(),
      started_at: body.started_at || null,
      supplier_id: body.supplier_id || null,
      source_location_id: body.source_location_id || body.location_id || null,
      target_location_id: body.target_location_id || body.location_id || null,
      comment: body.comment || body.reason || null,
      metadata: Object.assign({}, body.metadata || {}, {offline_pending: true, client_action_id: id}),
      lines: rows
    });
  }

  function applyLocal(action, body, id) {
    if (action === 'product_meta') {
      var product = productByKey(body.product_key);
      if (product) Object.keys(body).forEach(function (key) {
        if (key !== 'action' && key !== 'employee' && key !== 'product_key') product[key] = body[key];
      });
    } else if (action === 'product_meta_batch') {
      (body.items || []).forEach(function (item) { applyLocal('product_meta', item, id); });
    } else if (action === 'catalog_product_batch') {
      S.products = S.products || [];
      (body.items || []).forEach(function (item) {
        var product = item.old_product_key ? productByKey(item.old_product_key) : null;
        if (!product) {
          product = {balance: {quantity_base: 0, initialized: false}};
          S.products.push(product);
        }
        Object.assign(product, {
          name: item.name,
          category_name: item.category_name,
          category_sort: Number(item.category_sort || 0),
          package_size: Number(item.package_size || 1),
          stock_unit: item.stock_unit || 'ml',
          minimum_amount: Number(item.minimum_amount || 0),
          target_amount: Number(item.target_amount || 0),
          barcode: item.barcode || null,
          variance_recheck_amount: Number(item.variance_recheck_amount || 0),
          sell_by_bottle: item.sell_by_bottle === true,
          bottle_sale_price: item.bottle_sale_price == null ? null : Number(item.bottle_sale_price),
          portion_sale: item.portion_sale === true,
          portion_prices: Array.isArray(item.portion_prices) ? item.portion_prices : [],
          image_path: item.image_path || null,
          active: item.active !== false
        });
      });
    } else if (action === 'draft_sync') {
      var identity = draftIdentity(body);
      S.drafts = (S.drafts || []).filter(function (draft) { return draftIdentity(draft) !== identity; });
      S.drafts.unshift({
        id: 'pending:' + id,
        employee_name: body.employee,
        employee: body.employee,
        status: body.status || 'in_progress',
        started_at: body.started_at,
        active_seconds: Number(body.active_seconds || 0),
        filled_count: Number(body.filled_count || 0),
        total_count: Number(body.total_count || 0),
        payload: body.payload || {}
      });
    } else if (action === 'draft_delete') {
      var employee = String(body.employee || '').trim().toLowerCase();
      var startedAt = String(body.started_at || '').trim();
      S.drafts = (S.drafts || []).filter(function (draft) {
        var sameEmployee = String(draft.employee_name || '').trim().toLowerCase() === employee;
        var sameStart = !startedAt || String(draft.started_at || '').trim() === startedAt;
        return !(sameEmployee && sameStart);
      });
    } else if (action === 'supplier_upsert') {
      S.suppliers = S.suppliers || [];
      var supplier = S.suppliers.find(function (value) { return value.id === body.id; });
      if (supplier) Object.assign(supplier, body);
      else S.suppliers.push(Object.assign({active: true}, body, {id: body.id || 'pending:' + id}));
    } else if (action === 'location_upsert') {
      S.locations = S.locations || [];
      var location = S.locations.find(function (value) { return value.id === body.id; });
      if (location) Object.assign(location, body);
      else S.locations.push(Object.assign({active: true}, body, {id: body.id || 'pending:' + id}));
    } else if (action === 'supplier_link') {
      S.product_suppliers = S.product_suppliers || [];
      if (body.is_primary) S.product_suppliers.forEach(function (link) {
        if (link.product_key === body.product_key) link.is_primary = false;
      });
      var link = S.product_suppliers.find(function (value) {
        return value.product_key === body.product_key && value.supplier_id === body.supplier_id;
      });
      var linkValues = {
        product_key: body.product_key, supplier_id: body.supplier_id,
        supplier_sku: body.supplier_sku || null, is_primary: body.is_primary === true, active: true
      };
      if (link) Object.assign(link, linkValues); else S.product_suppliers.push(linkValues);
    } else if (action === 'purchase_request_create') {
      S.purchase_requests = S.purchase_requests || [];
      S.purchase_requests.unshift({
        id: 'pending:' + id, supplier_id: body.supplier_id || null, status: 'draft',
        created_by: body.employee || null, employee_name: body.employee || null,
        comment: body.comment || null, created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(), lines: body.lines || [], offline_pending: true
      });
    } else if (action === 'purchase_request_status') {
      var request = (S.purchase_requests || []).find(function (value) { return value.id === body.id; });
      if (request) request.status = body.status;
    } else if (['delivery', 'writeoff', 'stocktake', 'spot_stocktake', 'correction'].includes(action)) {
      var lines = body.lines || (body.product_key ? [{product_key: body.product_key, quantity_base: body.quantity_base}] : []);
      var rows = [];
      lines.forEach(function (line) {
        var p = productByKey(line.product_key);
        if (!p) return;
        p.balance = p.balance || {};
        var before = Number(p.balance.quantity_base || 0);
        var after = before;
        if (action === 'delivery') after += Number(line.quantity_base || 0);
        if (action === 'writeoff') after = Math.max(0, before - Number(line.quantity_base || 0));
        if (action === 'stocktake' || action === 'spot_stocktake') after = Math.max(0, Number(line.quantity_base || 0));
        if (action === 'correction') after = Math.max(0, before + Number(line.delta_quantity || 0));
        p.balance.quantity_base = after;
        p.balance.initialized = true;
        rows.push({
          product_key: line.product_key, product_name: p.name, category_name: p.category_name,
          package_size: p.package_size, stock_unit: p.stock_unit, before_quantity: before,
          change_quantity: after - before, after_quantity: after, comment: line.comment || null
        });
      });
      addPendingOperation(action, body, id, rows);
    } else if (action === 'transfer') {
      var balances = S.location_balances || [];
      S.location_balances = balances;
      (body.lines || []).forEach(function (line) {
        var amount = Number(line.quantity_base || 0);
        var source = balances.find(function (value) {
          return value.location_id === body.source_location_id && value.product_key === line.product_key;
        });
        var target = balances.find(function (value) {
          return value.location_id === body.target_location_id && value.product_key === line.product_key;
        });
        if (source) source.quantity_base = Math.max(0, Number(source.quantity_base || 0) - amount);
        if (target) target.quantity_base = Number(target.quantity_base || 0) + amount;
        else balances.push({location_id: body.target_location_id, product_key: line.product_key,
          quantity_base: amount, initialized: true});
      });
      addPendingOperation(action, body, id, []);
    }
    try { localStorage.setItem('bali-stock-v14-snapshot', JSON.stringify(S)); } catch (_) {}
  }

  async function updateStatus() {
    var count = 0;
    try { count = (await allItems()).length; } catch (_) {}
    var badge = document.getElementById('v14Pending');
    if (badge) badge.textContent = String(count);
    var status = document.getElementById('sync');
    if (!status) return;
    if (count) {
      status.textContent = '● сохранено • ожидает синхронизации: ' + count;
      status.className = 'status warn';
    } else if (navigator.onLine !== false) {
      status.textContent = '● синхронизировано';
      status.className = 'status ok';
    }
  }

  async function migrateLegacyQueue() {
    var legacy;
    try { legacy = JSON.parse(localStorage.getItem(LEGACY_QUEUE) || '[]'); } catch (_) { legacy = []; }
    if (!Array.isArray(legacy) || !legacy.length) return;
    for (var i = 0; i < legacy.length; i++) {
      var item = legacy[i] || {};
      if (item.action && durableActions.has(item.action)) await enqueue(item.action, item.body || {});
    }
    localStorage.removeItem(LEGACY_QUEUE);
  }

  async function pendingUpload(action, body, forceQueue) {
    if (!forceQueue && navigator.onLine !== false) {
      try { return await originalApi(action, body, true); }
      catch (error) { if (!networkError(error)) throw error; }
    }
    if (action === 'invoice_attachment_upload') {
      var attachmentId = uuid();
      await kvPut('pending_attachment', Object.assign({pending_id: attachmentId}, body));
      return {ok: true, queued: true, path: 'pending://invoice/' + attachmentId};
    }
    var scanId = uuid();
    await kvPut('pending_scan', Object.assign({pending_id: scanId}, body));
    return {ok: true, queued: true, id: 'pending://scan/' + scanId};
  }

  api = async function (action, body, needPin) {
    body = body || {};
    if (action === 'invoice_attachment_upload' || action === 'invoice_scan_save') {
      var pendingAttachment = await kvGet('pending_attachment');
      return pendingUpload(action, body, navigator.onLine === false || Boolean(pendingAttachment));
    }
    if (action === 'delivery') {
      var attachment = await kvGet('pending_attachment');
      var scan = await kvGet('pending_scan');
      if (attachment || scan) {
        var bundleId = await enqueue('delivery_bundle', {
          delivery: Object.assign({}, body, {attachment_url: attachment ? null : body.attachment_url}),
          attachment: attachment,
          scan: scan
        });
        await kvPut('pending_attachment', null);
        await kvPut('pending_scan', null);
        applyLocal('delivery', body, bundleId);
        var bundleResult = await flush(bundleId);
        return bundleResult || {ok: true, queued: true, snapshot: S, operation_id: 'pending:' + bundleId};
      }
    }
    if (!durableActions.has(action)) return originalApi(action, body, needPin);

    var id = await enqueue(action, body);
    var result = await flush(id);
    if (result) return result;
    applyLocal(action, body, id);
    try { render(); } catch (_) {}
    return {ok: true, queued: true, snapshot: S, id: 'pending:' + id, operation_id: 'pending:' + id};
  };

  snapshot = async function () {
    await migrateLegacyQueue();
    await flush(null);
    if ((await allItems()).length) {
      await updateStatus();
      try { render(); } catch (_) {}
      return S;
    }
    return originalSnapshot();
  };

  window.baliFlushPersistence = async function () {
    await migrateLegacyQueue();
    await flush(null);
    if (!(await allItems()).length) await originalSnapshot();
    return S;
  };

  window.addEventListener('online', function () { window.baliFlushPersistence().catch(function () {}); });
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) window.baliFlushPersistence().catch(function () {});
  });
  setInterval(function () {
    if (navigator.onLine !== false) window.baliFlushPersistence().catch(function () {});
  }, 12000);
  migrateLegacyQueue().then(function () { return flush(null); }).then(updateStatus).catch(function () {});
})();
