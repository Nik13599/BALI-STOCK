// BALI STOCK iPhone V12 — offline-first Web App layer.
const V12_DB_NAME = 'bali-stock-v12';
const V12_DB_VERSION = 1;
const V12_SYNC_API = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-sync-api';
const V12_OFFLINE_PIN_SHA256 = 'dc731f13f58f114657956a71d8f42886da116e604022b139581c16c43d7e3b94';

let __v12DbPromise = null;
let __v12Flushing = false;
let __v12PendingAttachment = null;
let __v12PendingScan = null;

const __v12OriginalApi = api;
const __v12OriginalSnapshot = snapshot;
const __v12OriginalRenderStock = renderStock;
const __v12OriginalWireStock = wireStock;

function __v12OpenDb() {
  if (__v12DbPromise) return __v12DbPromise;
  __v12DbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(V12_DB_NAME, V12_DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv');
      if (!db.objectStoreNames.contains('outbox')) db.createObjectStore('outbox', { keyPath: 'id' });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return __v12DbPromise;
}

async function __v12KvGet(key) {
  const db = await __v12OpenDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('kv', 'readonly');
    const req = tx.objectStore('kv').get(key);
    req.onsuccess = () => resolve(req.result ?? null);
    req.onerror = () => reject(req.error);
  });
}
async function __v12KvPut(key, value) {
  const db = await __v12OpenDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('kv', 'readwrite');
    tx.objectStore('kv').put(value, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
async function __v12OutboxAll() {
  const db = await __v12OpenDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('outbox', 'readonly');
    const req = tx.objectStore('outbox').getAll();
    req.onsuccess = () => resolve((req.result || []).sort((a,b) => String(a.created_at).localeCompare(String(b.created_at))));
    req.onerror = () => reject(req.error);
  });
}
async function __v12OutboxPut(item) {
  const db = await __v12OpenDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('outbox', 'readwrite');
    tx.objectStore('outbox').put(item);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
async function __v12OutboxDelete(id) {
  const db = await __v12OpenDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('outbox', 'readwrite');
    tx.objectStore('outbox').delete(id);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
async function __v12Coalesce(action, body) {
  if (!['draft_sync','draft_delete','product_meta'].includes(action)) return;
  const all = await __v12OutboxAll();
  for (const item of all) {
    const p = item.payload || {};
    let same = false;
    if (action === 'draft_sync' || action === 'draft_delete') {
      const queuedStarted = String(p.started_at || '').trim();
      const nextStarted = String(body.started_at || '').trim();
      same = (p.action === 'draft_sync' || p.action === 'draft_delete') &&
        String(p.employee || '').trim().toLowerCase() === String(body.employee || '').trim().toLowerCase() &&
        (!queuedStarted || !nextStarted || queuedStarted === nextStarted);
    } else if (action === 'product_meta') {
      same = p.action === 'product_meta' && p.product_key === body.product_key;
    }
    if (same) await __v12OutboxDelete(item.id);
  }
}
function __v12Id() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}
async function __v12Hash(value) {
  const bytes = new TextEncoder().encode(String(value));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,'0')).join('');
}
async function __v12EnsureOfflinePin() {
  if (!pin) pin = await ask('Введите PIN для офлайн-операции', 'password');
  if (!pin) throw Error('PIN не введён');
  if (await __v12Hash(pin) !== V12_OFFLINE_PIN_SHA256) {
    pin = null;
    throw Error('Неверный PIN');
  }
  return pin;
}
function __v12IsNetworkError(error) {
  const msg = String(error?.message || error || '');
  return navigator.onLine === false ||
    error instanceof TypeError ||
    /failed to fetch|load failed|network|offline|internet connection|the request timed out/i.test(msg);
}
function __v12Product(k) {
  return S.products.find(p => keyOf(p) === k);
}
function __v12EnsureBalance(p) {
  if (!p.balance || typeof p.balance !== 'object') p.balance = {};
  if (typeof p.balance.quantity_base !== 'number') p.balance.quantity_base = n(p.balance.quantity_base);
  return p.balance;
}
function __v12LocalOp(action, body, id, lineRows) {
  const op = {
    id: `local:${id}`,
    operation_id: `local:${id}`,
    operation_type: action,
    created_at: new Date().toISOString(),
    employee_name: body.employee || null,
    supplier_id: body.supplier_id || null,
    document_number: body.document_number || null,
    comment: body.comment || body.reason || null,
    source_location_id: body.source_location_id || null,
    target_location_id: body.target_location_id || null,
    attachment_url: null,
    metadata: { ...(body.metadata || {}), offline_pending: true, client_action_id: id },
    lines: lineRows
  };
  S.operations = Array.isArray(S.operations) ? S.operations : [];
  S.operations.unshift(op);
}
function __v12ApplyMutation(action, body, id) {
  const rows = [];
  if (action === 'delivery' || action === 'writeoff' || action === 'stocktake') {
    for (const line of (body.lines || [])) {
      const p = __v12Product(line.product_key);
      if (!p) continue;
      const b = __v12EnsureBalance(p);
      const before = n(b.quantity_base);
      let after = before;
      if (action === 'delivery') after = before + n(line.quantity_base);
      if (action === 'writeoff') after = Math.max(0, before - n(line.quantity_base));
      if (action === 'stocktake') after = Math.max(0, n(line.quantity_base));
      b.quantity_base = after;
      b.initialized = true;
      rows.push({
        product_key: line.product_key,
        product_name: p.name,
        category_name: p.category_name,
        stock_unit: p.stock_unit,
        package_size: p.package_size,
        before_quantity: before,
        change_quantity: after - before,
        after_quantity: after,
        comment: line.comment || null
      });
    }
    __v12LocalOp(action, body, id, rows);
  } else if (action === 'transfer') {
    for (const line of (body.lines || [])) {
      const p = __v12Product(line.product_key);
      if (!p) continue;
      const before = qty(p);
      rows.push({
        product_key: line.product_key,
        product_name: p.name,
        category_name: p.category_name,
        stock_unit: p.stock_unit,
        package_size: p.package_size,
        before_quantity: before,
        change_quantity: 0,
        after_quantity: before
      });
      const q = n(line.quantity_base);
      const balances = Array.isArray(S.location_balances) ? S.location_balances : [];
      const get = (loc) => balances.find(x=>x.location_id===loc && x.product_key===line.product_key);
      const src = get(body.source_location_id);
      const dst = get(body.target_location_id);
      if (src) src.quantity_base = Math.max(0, n(src.quantity_base)-q);
      if (dst) dst.quantity_base = n(dst.quantity_base)+q;
    }
    __v12LocalOp(action, body, id, rows);
  } else if (action === 'draft_sync') {
    S.drafts = Array.isArray(S.drafts) ? S.drafts : [];
    const emp = String(body.employee || '').trim().toLowerCase();
    S.drafts = S.drafts.filter(d=>String(d.employee_name||'').trim().toLowerCase()!==emp);
    S.drafts.unshift({
      id:`local:${id}`,
      employee_name:body.employee,
      status:body.status||'in_progress',
      started_at:body.started_at,
      active_seconds:n(body.active_seconds),
      filled_count:n(body.filled_count),
      total_count:n(body.total_count),
      payload:body.payload||{}
    });
  } else if (action === 'draft_delete') {
    const emp = String(body.employee || '').trim().toLowerCase();
    const started = String(body.started_at || '').trim();
    S.drafts = (S.drafts || []).filter(d=>{
      const sameEmployee = String(d.employee_name||'').trim().toLowerCase()===emp;
      const sameStarted = !started || String(d.started_at||'').trim()===started;
      return !(sameEmployee && sameStarted);
    });
  } else if (action === 'product_meta') {
    const p = __v12Product(body.product_key);
    if (p) {
      if (Object.hasOwn(body, 'minimum_amount')) p.minimum_amount = n(body.minimum_amount);
      if (Object.hasOwn(body, 'target_amount')) p.target_amount = n(body.target_amount);
      if (Object.hasOwn(body, 'barcode')) p.barcode = body.barcode || null;
      if (Object.hasOwn(body, 'variance_recheck_amount')) p.variance_recheck_amount = n(body.variance_recheck_amount);
    }
  } else if (action === 'purchase_request_create') {
    S.purchase_requests = Array.isArray(S.purchase_requests) ? S.purchase_requests : [];
    S.purchase_requests.unshift({
      id:`local:${id}`, status:'draft', created_at:new Date().toISOString(),
      employee_name:body.employee, supplier_id:body.supplier_id||null,
      comment:body.comment||null, lines:body.lines||[], offline_pending:true
    });
  }
  S.version = n(S.version) + 1;
}
async function __v12SaveSnapshot() {
  try { await __v12KvPut('snapshot', S); } catch (_) {}
}
async function __v12LoadSnapshot() {
  try { return await __v12KvGet('snapshot'); } catch (_) { return null; }
}
async function __v12PendingCount() {
  try { return (await __v12OutboxAll()).length; } catch (_) { return 0; }
}
async function __v12SetStatus(extra='') {
  const el = $('#sync');
  if (!el) return;
  const count = await __v12PendingCount();
  if (count > 0) {
    el.textContent = `● ${count} ожидает${extra ? ' • '+extra : ''}`;
    el.className = 'status warn';
    el.style.cursor = 'pointer';
    el.title = 'Нажмите, чтобы синхронизировать';
  } else if (!navigator.onLine) {
    el.textContent = '● офлайн';
    el.className = 'status warn';
  } else {
    el.textContent = '● синхронизировано';
    el.className = 'status ok';
  }
}
async function __v12QueueMutation(action, body) {
  if (['supplier_upsert','location_upsert'].includes(action)) {
    throw Error('Создание нового поставщика или места хранения требует подключения к интернету.');
  }
  await __v12Coalesce(action, body);
  const id = __v12Id();
  let payload;
  if (action === 'delivery' && (__v12PendingAttachment || __v12PendingScan)) {
    payload = {
      client_action_id:id,
      action:'delivery_bundle',
      delivery:{...body, attachment_url:null},
      attachment:__v12PendingAttachment,
      scan:__v12PendingScan
    };
    __v12PendingAttachment = null;
    __v12PendingScan = null;
  } else {
    payload = {client_action_id:id, action, ...body};
  }
  const item = {id, action:payload.action, payload, created_at:new Date().toISOString(), last_error:null};
  await __v12OutboxPut(item);
  __v12ApplyMutation(action, body, id);
  await __v12SaveSnapshot();
  await __v12SetStatus('сохранено на iPhone');
  try { render(); } catch (_) {}
  if (navigator.onLine && pin) setTimeout(()=>__v12Flush(false), 50);
  return {ok:true, queued:true, client_action_id:id, snapshot:S, id:`local:${id}`, operation_id:`local:${id}`, path:'offline://queued'};
}
async function __v12Flush(askForPin=false) {
  if (__v12Flushing) return;
  let items = await __v12OutboxAll();
  if (!items.length) { await __v12SetStatus(); return; }
  if (!navigator.onLine) { await __v12SetStatus('нет сети'); return; }
  if (!pin) {
    if (!askForPin) { await __v12SetStatus('нужен PIN'); return; }
    await __v12EnsureOfflinePin();
  }
  __v12Flushing = true;
  try {
    for (const item of items) {
      const r = await fetch(V12_SYNC_API, {
        method:'POST',
        headers:{apikey:KEY,Accept:'application/json','Content-Type':'application/json','x-bali-stock-pin':pin},
        body:JSON.stringify(item.payload)
      });
      const d = await r.json().catch(()=>({}));
      if (!r.ok) {
        if (r.status === 401 || /pin|парол/i.test(String(d.error||''))) pin = null;
        item.last_error = d.error || `HTTP ${r.status}`;
        await __v12OutboxPut(item);
        throw Error(item.last_error);
      }
      await __v12OutboxDelete(item.id);
      await __v12SetStatus('отправка…');
    }
    const remain = await __v12OutboxAll();
    if (!remain.length) {
      try {
        const fresh = await __v12OriginalSnapshot();
        if (fresh) S = fresh;
        await __v12SaveSnapshot();
      } catch (_) {}
    }
    await __v12SetStatus();
  } catch (e) {
    await __v12SetStatus('ошибка отправки');
    if (askForPin) toast(`Синхронизация: ${e.message}`, true);
  } finally {
    __v12Flushing = false;
  }
}

api = async function(action, body={}, needPin=false) {
  if (action === 'authorize') {
    try {
      const d = await __v12OriginalApi(action, body, needPin);
      await __v12SetStatus();
      return d;
    } catch (e) {
      if (!__v12IsNetworkError(e)) throw e;
      await __v12EnsureOfflinePin();
      await __v12SetStatus('офлайн');
      return {ok:true, offline:true};
    }
  }

  if (action === 'invoice_attachment_upload' && (!navigator.onLine || __v12PendingAttachment)) {
    await __v12EnsureOfflinePin();
    __v12PendingAttachment = {...body};
    return {path:`offline://invoice/${__v12Id()}`};
  }
  if (action === 'invoice_scan_save' && (__v12PendingAttachment || !navigator.onLine)) {
    await __v12EnsureOfflinePin();
    __v12PendingScan = {...body};
    return {id:`offline-scan-${__v12Id()}`};
  }
  if (action === 'delivery' && (__v12PendingAttachment || __v12PendingScan)) {
    await __v12EnsureOfflinePin();
    return __v12QueueMutation(action, body);
  }

  try {
    const d = await __v12OriginalApi(action, body, needPin);
    if (d?.snapshot) {
      S = d.snapshot;
      await __v12SaveSnapshot();
    }
    await __v12SetStatus();
    return d;
  } catch (e) {
    if (!__v12IsNetworkError(e)) throw e;
    if (action === 'invoice_attachment_upload') {
      await __v12EnsureOfflinePin();
      __v12PendingAttachment = {...body};
      return {path:`offline://invoice/${__v12Id()}`};
    }
    if (action === 'invoice_scan_save') {
      await __v12EnsureOfflinePin();
      __v12PendingScan = {...body};
      return {id:`offline-scan-${__v12Id()}`};
    }
    const queueable = ['delivery','stocktake','writeoff','transfer','draft_sync','draft_delete','product_meta','purchase_request_create'];
    if (!queueable.includes(action)) throw e;
    if (needPin) await __v12EnsureOfflinePin();
    return __v12QueueMutation(action, body);
  }
};

snapshot = async function() {
  const pending = await __v12PendingCount();
  if (pending > 0) {
    const cached = await __v12LoadSnapshot();
    if (cached) S = cached;
    await __v12SetStatus(pin && navigator.onLine ? 'отправка…' : (navigator.onLine ? 'нужен PIN' : 'офлайн'));
    try { render(); } catch (_) {}
    if (pin && navigator.onLine) setTimeout(()=>__v12Flush(false), 25);
    return S;
  }
  try {
    const d = await __v12OriginalSnapshot();
    if (d) S = d;
    await __v12SaveSnapshot();
    await __v12SetStatus();
    return d;
  } catch (e) {
    const cached = await __v12LoadSnapshot();
    if (cached) {
      S = cached;
      await __v12SetStatus('офлайн');
      try { render(); } catch (_) {}
      return cached;
    }
    throw e;
  }
};

renderStock = function() {
  return `<div class="toolbar noPrint"><button id="v12Scan">📷 Сканировать QR / штрихкод</button><button id="v12ManualCode" class="secondary">⌨️ Ввести код</button></div>` + __v12OriginalRenderStock();
};
wireStock = function() {
  __v12OriginalWireStock();
  const scan = $('#v12Scan');
  const manual = $('#v12ManualCode');
  if (scan) scan.onclick = __v12StartScanner;
  if (manual) manual.onclick = async()=> {
    const code = await ask('Введите QR / штрихкод');
    if (code) await __v12HandleCode(code);
  };
};
async function __v12HandleCode(raw) {
  const resolved = await __v12ResolveProductCode(raw);
  if (resolved) __v12ShowScannedProduct(resolved.product, resolved.code, resolved.manual);
}
async function __v12ResolveProductCode(raw) {
  const code = String(raw || '').trim();
  if (!code) return null;
  const p = S.products.find(x=>String(x.barcode||'').trim().toLowerCase() === code.toLowerCase());
  if (p) return {product:p, code, manual:false};
  const action = await __v12ChooseUnknownCodeAction(code);
  if (!action) return null;
  const p2 = await chooseProduct(action === 'assign' ? 'Выберите товар для назначения кода' : 'Найдите товар вручную');
  if (!p2) return null;
  if (action === 'manual') return {product:p2, code, manual:true};
  await api('authorize',{},true);
  const employee = await ask('ФИО сотрудника');
  if (!employee) return null;
  await api('product_meta',{
    employee,
    product_key:keyOf(p2),
    minimum_amount:n(p2.minimum_amount),
    target_amount:n(p2.target_amount),
    barcode:code,
    variance_recheck_amount:n(p2.variance_recheck_amount)
  },true);
  toast(navigator.onLine ? 'Код привязан к товару' : 'Код сохранён на iPhone и будет синхронизирован');
  render();
  const current = S.products.find(x=>keyOf(x)===keyOf(p2)) || p2;
  return {product:{...current, barcode:code}, code, manual:false};
}
function __v12ShowScannedProduct(product, code, manual=false) {
  openModal(`<h2>${manual?'Товар выбран вручную':'Товар найден'}</h2><div class="card"><div class="name">${esc(product.name)}</div><div class="muted">${esc(product.category_name)}${manual?'':' • код '+esc(code)}</div><div class="amount">${init(product)?esc(parts(qty(product),product)):'Остаток не введён'}</div></div><button id="v12Hist" class="secondary" style="width:100%">История товара</button><button id="v12ProductClose" class="secondary" style="width:100%;margin-top:8px">Закрыть</button>`);
  $('#v12Hist').onclick = ()=>{ closeModal(); showProductHistory(keyOf(product)); };
  $('#v12ProductClose').onclick = closeModal;
}
function __v12ChooseUnknownCodeAction(code) {
  return new Promise(resolve=>{
    openModal(`<h2>Код не найден</h2><p class="muted">Код ${esc(code)} не привязан ни к одному товару.</p><button id="v12AssignCode" style="width:100%">Назначить код товару</button><button id="v12FindManual" class="secondary" style="width:100%;margin-top:8px">Найти товар вручную</button><button id="v12UnknownCancel" class="secondary" style="width:100%;margin-top:8px">Закрыть</button>`);
    $('#v12AssignCode').onclick=()=>{closeModal();resolve('assign');};
    $('#v12FindManual').onclick=()=>{closeModal();resolve('manual');};
    $('#v12UnknownCancel').onclick=()=>{closeModal();resolve(null);};
  });
}
async function __v12StartScanner() {
  if (typeof Html5Qrcode === 'undefined') {
    toast('Модуль камеры ещё не загружен. Используйте «Ввести код».', true);
    return;
  }
  openModal(`<h2>Сканирование</h2><div id="v12reader" style="width:100%;min-height:260px;border-radius:14px;overflow:hidden"></div><p class="muted">Наведите камеру на QR-код или штрихкод товара.</p><button id="v12ScanCancel" class="secondary" style="width:100%">Закрыть</button>`);
  const qr = new Html5Qrcode('v12reader');
  let done = false;
  const stop = async()=>{ try { await qr.stop(); } catch(_) {} try { qr.clear(); } catch(_) {} };
  $('#v12ScanCancel').onclick = async()=>{ await stop(); closeModal(); };
  try {
    await qr.start(
      {facingMode:'environment'},
      {fps:10, qrbox:{width:250,height:160}},
      async(decoded)=>{
        if (done) return;
        done = true;
        await stop();
        closeModal();
        await __v12HandleCode(decoded);
      },
      ()=>{}
    );
  } catch (e) {
    await stop();
    closeModal();
    toast('Не удалось открыть камеру: '+e, true);
  }
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('./sw.js').catch(()=>{});
}
window.addEventListener('online', ()=>{ __v12SetStatus('сеть восстановлена'); __v12Flush(false); });
window.addEventListener('offline', ()=>__v12SetStatus('офлайн'));
document.addEventListener('visibilitychange', ()=>{ if (!document.hidden && navigator.onLine) __v12Flush(false); });
setInterval(()=>{ if (navigator.onLine) __v12Flush(false); else __v12SetStatus('офлайн'); }, 12000);
setTimeout(()=>{
  const s = $('#sync');
  if (s) s.onclick = ()=>__v12Flush(true);
  __v12SetStatus();
}, 250);
