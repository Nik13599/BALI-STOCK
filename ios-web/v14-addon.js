(() => {
  'use strict';

  const QUEUE_KEY = 'bali-stock-v14-queue';
  const state = { staged: new Map(), observer: null };

  const asNumber = (value, fallback = 0) => {
    const parsed = Number(String(value ?? '').replace(',', '.'));
    return Number.isFinite(parsed) ? parsed : fallback;
  };
  const asInt = (value, fallback = 0) => {
    const parsed = Number.parseInt(String(value ?? ''), 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  };
  const clean = (value) => String(value ?? '').trim();
  const stockUnitLabel = (unit) => unit === 'pcs' ? 'шт.' : unit === 'g' ? 'г' : 'мл';
  const productKey = (product) => typeof keyOf === 'function'
    ? keyOf(product)
    : `${clean(product.name).toLowerCase()}|${product.stock_unit || 'ml'}|${asInt(product.package_size, 1)}`;

  function readQueue() {
    try {
      const raw = JSON.parse(localStorage.getItem(QUEUE_KEY) || '[]');
      return Array.isArray(raw) ? raw : [];
    } catch (_) {
      return [];
    }
  }

  function saveQueue(items) {
    localStorage.setItem(QUEUE_KEY, JSON.stringify(items));
    const badge = document.getElementById('v14Pending');
    if (badge) badge.textContent = String(items.length);
  }

  async function ensurePin() {
    try {
      if (typeof pin !== 'undefined' && clean(pin)) return true;
      if (typeof ask !== 'function' || typeof api !== 'function') return false;
      const value = await ask('Введите пароль доступа', 'password');
      if (!value) return false;
      pin = String(value);
      await api('authorize', {}, true);
      return true;
    } catch (error) {
      try { pin = ''; } catch (_) {}
      if (typeof toast === 'function') toast(error?.message || String(error), true);
      return false;
    }
  }

  function sourceProducts() {
    try {
      return Array.isArray(S?.products) ? S.products.filter((p) => p && p.active !== false) : [];
    } catch (_) {
      return [];
    }
  }

  function categories() {
    const map = new Map();
    for (const p of sourceProducts()) {
      const name = clean(p.category_name) || 'Прочее';
      if (!map.has(name)) map.set(name, asInt(p.category_sort));
    }
    return [...map.entries()].sort((a, b) => a[1] - b[1] || a[0].localeCompare(b[0], 'ru'));
  }

  function cloneEdit(product) {
    return {
      old_product_key: productKey(product),
      name: clean(product.name),
      category_name: clean(product.category_name) || 'Прочее',
      category_sort: asInt(product.category_sort),
      package_size: Math.max(1, asInt(product.package_size, 1)),
      stock_unit: clean(product.stock_unit) || 'ml',
      minimum_amount: Math.max(0, asInt(product.minimum_amount)),
      target_amount: Math.max(0, asInt(product.target_amount)),
      barcode: clean(product.barcode) || null,
      default_cost: product.default_cost == null ? null : asNumber(product.default_cost),
      cost_currency: clean(product.cost_currency) || 'BYN',
      variance_recheck_amount: Math.max(0, asInt(product.variance_recheck_amount)),
      active: true,
      sell_by_bottle: product.sell_by_bottle === true,
      bottle_sale_price: product.bottle_sale_price == null ? null : asNumber(product.bottle_sale_price),
      portion_sale: product.portion_sale === true,
      portion_prices: Array.isArray(product.portion_prices)
        ? product.portion_prices.map((x) => ({ ml: Math.max(1, asInt(x.ml, 1)), price: Math.max(0, asNumber(x.price)) }))
        : [],
      image_path: product.image_path || null,
    };
  }

  function stagedFor(product) {
    return state.staged.get(productKey(product)) || cloneEdit(product);
  }

  function sameEdit(product, edit) {
    return JSON.stringify(cloneEdit(product)) === JSON.stringify(edit);
  }

  function setStaged(product, edit) {
    const key = productKey(product);
    if (sameEdit(product, edit)) state.staged.delete(key);
    else state.staged.set(key, edit);
  }

  function escapeHtml(value) {
    if (typeof esc === 'function') return esc(String(value ?? ''));
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function showModal(html) {
    if (typeof openModal === 'function') openModal(html);
  }

  function close() {
    if (typeof closeModal === 'function') closeModal();
  }

  function editorRows(filter = '') {
    const q = clean(filter).toLowerCase();
    const rows = sourceProducts().filter((product) => {
      const edit = stagedFor(product);
      return !q || `${edit.name} ${edit.category_name} ${edit.barcode || ''}`.toLowerCase().includes(q);
    });
    return rows.map((product) => {
      const edit = stagedFor(product);
      const changed = state.staged.has(productKey(product));
      const portionText = edit.portion_prices.length
        ? edit.portion_prices.map((p) => `${p.ml}/${Number(p.price).toFixed(2)}`).join(' • ')
        : 'порции не заданы';
      return `<button class="listbtn v14BatchProduct" data-key="${escapeHtml(productKey(product))}">
        <div class="row">
          <div class="grow">
            <div class="name">${escapeHtml(edit.name)} ${changed ? '<span style="color:#39ff6a">• ИЗМЕНЕНО</span>' : ''}</div>
            <div class="muted">${escapeHtml(edit.category_name)} • ${edit.package_size} ${stockUnitLabel(edit.stock_unit)} • код ${escapeHtml(edit.barcode || '—')}</div>
            <div class="muted">Мин. ${edit.minimum_amount} • цель ${edit.target_amount} • бутылка ${edit.sell_by_bottle ? (edit.bottle_sale_price ?? '—') + ' BYN' : 'выкл.'} • ${escapeHtml(portionText)}</div>
          </div>
          <b>✎</b>
        </div>
      </button>`;
    }).join('');
  }

  function renderBatchList(filter = '') {
    showModal(`<h2>Массовое редактирование</h2>
      <div class="muted">Все изменения остаются черновиком до одного общего подтверждения. Закупочная цена здесь не редактируется — она приходит только из поставки.</div>
      <input id="v14BatchSearch" class="input" style="margin-top:12px" placeholder="Название / категория / код" value="${escapeHtml(filter)}">
      <div id="v14BatchRows" style="margin-top:10px;max-height:55vh;overflow:auto">${editorRows(filter)}</div>
      <div class="toolbar" style="margin-top:12px">
        <button id="v14BatchDiscard" class="secondary">ОТМЕНИТЬ</button>
        <button id="v14BatchConfirm">ПОДТВЕРДИТЬ • <span id="v14BatchCount">${state.staged.size}</span></button>
      </div>`);

    const search = document.getElementById('v14BatchSearch');
    if (search) search.oninput = (event) => refreshBatchRows(event.target.value);
    const discard = document.getElementById('v14BatchDiscard');
    if (discard) discard.onclick = () => { state.staged.clear(); close(); };
    const confirm = document.getElementById('v14BatchConfirm');
    if (confirm) confirm.onclick = confirmBatch;
    wireBatchRows(filter);
  }

  function refreshBatchRows(filter = '') {
    const holder = document.getElementById('v14BatchRows');
    if (holder) holder.innerHTML = editorRows(filter);
    const count = document.getElementById('v14BatchCount');
    if (count) count.textContent = String(state.staged.size);
    wireBatchRows(filter);
  }

  function wireBatchRows(filter) {
    document.querySelectorAll('.v14BatchProduct').forEach((button) => {
      button.onclick = () => {
        const product = sourceProducts().find((p) => productKey(p) === button.dataset.key);
        if (product) renderProductEditor(product, filter);
      };
    });
  }

  function portionRows(edit) {
    const portions = edit.portion_prices.length ? edit.portion_prices : [{ ml: 40, price: 0 }];
    return portions.map((portion, index) => `<div class="grid2 v14PortionRow" data-index="${index}" style="margin:7px 0">
      <input class="input v14PortionMl" inputmode="numeric" value="${portion.ml}" placeholder="Объём">
      <input class="input v14PortionPrice" inputmode="decimal" value="${portion.price}" placeholder="Цена BYN">
    </div>`).join('');
  }

  function renderProductEditor(product, returnFilter = '') {
    const edit = structuredClone(stagedFor(product));
    const cats = categories();
    showModal(`<h2>${escapeHtml(product.name)}</h2>
      <input id="v14Name" class="input" value="${escapeHtml(edit.name)}" placeholder="Название">
      <select id="v14Category" class="input" style="margin-top:8px">
        ${cats.map(([name]) => `<option ${name === edit.category_name ? 'selected' : ''}>${escapeHtml(name)}</option>`).join('')}
      </select>
      <div class="grid2" style="margin-top:8px">
        <select id="v14Unit" class="input">
          <option value="ml" ${edit.stock_unit === 'ml' ? 'selected' : ''}>мл</option>
          <option value="g" ${edit.stock_unit === 'g' ? 'selected' : ''}>г</option>
          <option value="pcs" ${edit.stock_unit === 'pcs' ? 'selected' : ''}>шт.</option>
        </select>
        <input id="v14Package" class="input" inputmode="numeric" value="${edit.package_size}" placeholder="Объём / упаковка">
      </div>
      <input id="v14Barcode" class="input" style="margin-top:8px" value="${escapeHtml(edit.barcode || '')}" placeholder="Штрихкод / код">
      <div class="grid2" style="margin-top:8px">
        <input id="v14Minimum" class="input" inputmode="numeric" value="${edit.minimum_amount}" placeholder="Минимум">
        <input id="v14Target" class="input" inputmode="numeric" value="${edit.target_amount}" placeholder="Цель">
      </div>
      <input id="v14Recheck" class="input" style="margin-top:8px" inputmode="numeric" value="${edit.variance_recheck_amount}" placeholder="Порог перепроверки">
      <div class="card" style="margin-top:10px"><b>Последняя закупка: ${edit.default_cost == null ? '—' : edit.default_cost + ' ' + escapeHtml(edit.cost_currency)}</b><div class="muted">Меняется только реальной поставкой.</div></div>
      <label class="row card"><input id="v14BottleToggle" type="checkbox" ${edit.sell_by_bottle ? 'checked' : ''}><b>Продажа бутылкой</b></label>
      <input id="v14BottlePrice" class="input" inputmode="decimal" value="${edit.bottle_sale_price ?? ''}" placeholder="Цена бутылки, BYN">
      <label class="row card" style="margin-top:8px"><input id="v14PortionToggle" type="checkbox" ${edit.portion_sale ? 'checked' : ''}><b>Порционная продажа</b></label>
      <div id="v14Portions">${portionRows(edit)}</div>
      <button id="v14AddPortion" class="secondary" style="width:100%;margin-top:6px">+ Добавить порцию</button>
      <div class="toolbar" style="margin-top:12px">
        <button id="v14Back" class="secondary">Назад</button>
        <button id="v14Apply">Применить в черновик</button>
      </div>`);

    const unit = document.getElementById('v14Unit');
    const packageInput = document.getElementById('v14Package');
    if (unit) unit.onchange = () => {
      if (unit.value === 'pcs') {
        packageInput.value = '1';
        packageInput.disabled = true;
      } else {
        packageInput.disabled = false;
      }
    };
    if (unit?.value === 'pcs') packageInput.disabled = true;

    const back = document.getElementById('v14Back');
    if (back) back.onclick = () => renderBatchList(returnFilter);
    const addPortion = document.getElementById('v14AddPortion');
    if (addPortion) addPortion.onclick = () => {
      const holder = document.getElementById('v14Portions');
      holder.insertAdjacentHTML('beforeend', '<div class="grid2 v14PortionRow" style="margin:7px 0"><input class="input v14PortionMl" inputmode="numeric" value="40" placeholder="Объём"><input class="input v14PortionPrice" inputmode="decimal" value="" placeholder="Цена BYN"></div>');
    };
    const apply = document.getElementById('v14Apply');
    if (apply) apply.onclick = () => applyEdit(product, edit, returnFilter);
  }

  function applyEdit(product, edit, returnFilter) {
    const name = clean(document.getElementById('v14Name')?.value);
    const category = clean(document.getElementById('v14Category')?.value);
    const unit = clean(document.getElementById('v14Unit')?.value) || 'ml';
    const packageSize = unit === 'pcs' ? 1 : asInt(document.getElementById('v14Package')?.value);
    const minimum = asInt(document.getElementById('v14Minimum')?.value, -1);
    const target = asInt(document.getElementById('v14Target')?.value, -1);
    const recheck = asInt(document.getElementById('v14Recheck')?.value, -1);
    const bottleEnabled = document.getElementById('v14BottleToggle')?.checked === true;
    const bottleRaw = clean(document.getElementById('v14BottlePrice')?.value);
    const bottlePrice = bottleRaw ? asNumber(bottleRaw, -1) : null;
    const portionEnabled = document.getElementById('v14PortionToggle')?.checked === true;
    const portions = [...document.querySelectorAll('.v14PortionRow')].map((row) => ({
      ml: asInt(row.querySelector('.v14PortionMl')?.value, -1),
      price: asNumber(row.querySelector('.v14PortionPrice')?.value, -1),
    }));

    if (!name || !category || packageSize <= 0 || minimum < 0 || target < 0 || recheck < 0) {
      toast('Проверьте название, категорию, упаковку, минимум и цель', true);
      return;
    }
    if (bottleEnabled && (bottlePrice == null || bottlePrice < 0)) {
      toast('Укажите цену бутылки', true);
      return;
    }
    if (portions.some((x) => x.ml <= 0 || x.price < 0)) {
      toast('Проверьте объём и цену порций', true);
      return;
    }
    if (portionEnabled && portions.length === 0) {
      toast('Добавьте хотя бы одну порцию', true);
      return;
    }

    const selectedCategory = categories().find(([cat]) => cat === category);
    Object.assign(edit, {
      name,
      category_name: category,
      category_sort: selectedCategory ? selectedCategory[1] : edit.category_sort,
      stock_unit: unit,
      package_size: packageSize,
      barcode: clean(document.getElementById('v14Barcode')?.value) || null,
      minimum_amount: minimum,
      target_amount: target,
      variance_recheck_amount: recheck,
      sell_by_bottle: bottleEnabled,
      bottle_sale_price: bottlePrice,
      portion_sale: portionEnabled,
      portion_prices: portions,
    });
    setStaged(product, edit);
    renderBatchList(returnFilter);
  }

  async function confirmBatch() {
    if (state.staged.size === 0) {
      toast('Изменений нет');
      return;
    }
    if (!await ensurePin()) return;
    const employee = await ask('ФИО сотрудника');
    if (!employee || !clean(employee)) return;

    const identities = new Set();
    for (const edit of state.staged.values()) {
      const identity = `${edit.name.toLowerCase()}|${edit.stock_unit}|${edit.package_size}`;
      if (identities.has(identity)) {
        toast(`Дублирующийся SKU: ${edit.name}`, true);
        return;
      }
      identities.add(identity);
    }

    const body = {
      employee: clean(employee),
      items: [...state.staged.values()],
    };

    try {
      if (!navigator.onLine) {
        const queue = readQueue();
        queue.push({ action: 'catalog_product_batch', body, created_at: new Date().toISOString() });
        saveQueue(queue);
        state.staged.clear();
        close();
        toast('Пакет изменений сохранён офлайн и ожидает синхронизации');
        return;
      }
      const result = await api('catalog_product_batch', body, true);
      if (result?.snapshot) {
        S = result.snapshot;
        localStorage.setItem('bali-stock-v14-snapshot', JSON.stringify(S));
      }
      state.staged.clear();
      close();
      if (typeof render === 'function') render();
      toast(`Изменено товаров: ${body.items.length}`);
    } catch (error) {
      toast(error?.message || String(error), true);
    }
  }

  async function openBatchEditor() {
    if (!await ensurePin()) return;
    state.staged.clear();
    renderBatchList();
  }

  function injectButton() {
    try {
      if (typeof tab === 'undefined' || tab !== 'stock') return;
      if (document.getElementById('v14BatchEdit')) return;
      const search = document.getElementById('stockSearchV14');
      const toolbar = search?.closest('.toolbar');
      if (!toolbar) return;
      const button = document.createElement('button');
      button.id = 'v14BatchEdit';
      button.className = 'secondary';
      button.textContent = '✎ Редактировать';
      button.onclick = openBatchEditor;
      toolbar.appendChild(button);
    } catch (_) {}
  }

  function start() {
    injectButton();
    const app = document.getElementById('app') || document.body;
    state.observer = new MutationObserver(() => injectButton());
    state.observer.observe(app, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
