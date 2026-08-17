/* BALI STOCK iPhone parity enhancements. Loaded after ios-web/v2.html. */
(() => {
  const baseRenderDelivery = renderDelivery;
  renderDelivery = function () {
    const pending = S.products.filter(p => p.active !== false && !init(p));
    if (pending.length) {
      return `<h2>Принять поставку</h2><div class="card"><div class="name">Сначала проведите первичный переучёт</div><p class="muted">У ${pending.length} позиций ещё не введён фактический остаток. Поставка станет доступна только после полного первичного пересчёта всего склада.</p><button onclick="setTab('count')">Перейти к переучёту</button></div>`;
    }
    return baseRenderDelivery();
  };

  const baseRenderControl = renderControl;
  renderControl = function () {
    const html = baseRenderControl();
    const value = S.products.filter(p => init(p) && p.default_cost != null && n(p.package_size) > 0)
      .reduce((sum, p) => sum + (qty(p) / Math.max(1, n(p.package_size))) * Number(p.default_cost || 0), 0);
    return html + `<div class="cat"><span>Финансовый контроль</span></div><div class="card"><div class="muted">Расчётная закупочная стоимость текущего склада</div><div class="amount">${money(value, 'BYN')}</div><div class="muted" style="margin-top:6px">Считается только по позициям, для которых сохранена закупочная цена.</div></div>`;
  };

  const baseWireControl = wireControl;
  wireControl = function () {
    baseWireControl();
    const edit = $('#editProd');
    if (!edit) return;
    const supplierButton = document.createElement('button');
    supplierButton.className = 'secondary';
    supplierButton.style.cssText = 'width:100%;margin-top:8px';
    supplierButton.textContent = 'Поставщики этой позиции';
    supplierButton.onclick = linkProductSupplierWeb;
    edit.parentElement.appendChild(supplierButton);

    const barcodeButton = document.createElement('button');
    barcodeButton.className = 'secondary';
    barcodeButton.style.cssText = 'width:100%;margin-top:8px';
    barcodeButton.textContent = 'Сканировать штрихкод товара';
    barcodeButton.onclick = scanBarcodeWeb;
    edit.parentElement.appendChild(barcodeButton);
  };

  async function linkProductSupplierWeb() {
    try {
      await api('authorize', {}, true);
      const p = S.products.find(x => keyOf(x) === $('#ctlProd')?.value);
      if (!p) throw Error('Позиция не выбрана');
      if (!S.suppliers.length) {
        if (await confirmBox('Поставщиков нет', 'Добавить нового поставщика сейчас?')) {
          await addSupplier();
        }
        if (!S.suppliers.length) return;
      }
      const links = S.product_suppliers.filter(x => x.product_key === keyOf(p) && x.active !== false);
      const supplierOptions = S.suppliers.filter(x => x.active !== false)
        .map(s => `<option value="${s.id}">${esc(s.name)}</option>`).join('');
      openModal(`<h2>Поставщики: ${esc(p.name)}</h2>
        <div class="muted">К одной позиции можно привязать несколько поставщиков.</div>
        <div style="margin:10px 0">${links.length ? links.map(l => {
          const s = S.suppliers.find(x => x.id === l.supplier_id);
          return `<div class="card"><b>${esc(s?.name || 'Поставщик')}</b>${l.is_primary ? ' <span class="pill">основной</span>' : ''}<div class="muted">${l.supplier_sku ? 'арт. ' + esc(l.supplier_sku) + ' • ' : ''}${l.last_price != null ? money(l.last_price, l.currency || 'BYN') : 'цена не указана'}</div></div>`;
        }).join('') : '<div class="muted">Поставщики ещё не привязаны.</div>'}</div>
        <select id="linkSup" class="input">${supplierOptions}</select>
        <input id="linkSku" class="input" style="margin-top:8px" placeholder="Артикул у поставщика">
        <input id="linkPrice" class="input" style="margin-top:8px" inputmode="decimal" placeholder="Последняя цена, BYN">
        <label style="display:block;margin:10px 0"><input id="linkPrimary" type="checkbox"> Основной поставщик</label>
        <div class="toolbar"><button id="linkSave">Привязать</button><button id="linkClose" class="secondary">Закрыть</button></div>`);
      $('#linkClose').onclick = closeModal;
      $('#linkSave').onclick = async () => {
        try {
          const priceText = $('#linkPrice').value.trim();
          await api('supplier_link', {
            product_key: keyOf(p),
            supplier_id: $('#linkSup').value,
            supplier_sku: $('#linkSku').value.trim() || null,
            last_price: priceText ? Number(priceText.replace(',', '.')) : null,
            currency: 'BYN',
            is_primary: $('#linkPrimary').checked
          }, true);
          closeModal();
          toast('Поставщик привязан');
          await snapshot();
        } catch (e) { toast(e.message, true); }
      };
    } catch (e) { toast(e.message, true); }
  }

  async function scanBarcodeWeb() {
    const p = S.products.find(x => keyOf(x) === $('#ctlProd')?.value);
    if (!p) return;
    let code = null;
    if ('BarcodeDetector' in window && navigator.mediaDevices?.getUserMedia) {
      try {
        const detector = new BarcodeDetector({ formats: ['ean_13','ean_8','code_128','code_39','upc_a','upc_e','qr_code'] });
        openModal(`<h2>Сканировать штрихкод</h2><video id="barcodeVideo" autoplay playsinline style="width:100%;border-radius:14px;background:#000"></video><div class="muted" style="margin-top:8px">Наведите камеру на код.</div><button id="barcodeCancel" class="secondary" style="width:100%;margin-top:10px">Отмена</button>`);
        const video = $('#barcodeVideo');
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
        video.srcObject = stream;
        let cancelled = false;
        $('#barcodeCancel').onclick = () => { cancelled = true; stream.getTracks().forEach(t => t.stop()); closeModal(); };
        for (let i = 0; i < 120 && !cancelled && !code; i++) {
          await new Promise(r => setTimeout(r, 150));
          try {
            const result = await detector.detect(video);
            if (result.length) code = result[0].rawValue;
          } catch (_) {}
        }
        stream.getTracks().forEach(t => t.stop());
        if (!cancelled) closeModal();
      } catch (_) {
        closeModal();
      }
    }
    if (!code) code = await ask('Введите штрихкод / QR вручную', 'text', p.barcode || '');
    if (!code) return;
    try {
      await api('authorize', {}, true);
      const employee = await ask('ФИО сотрудника');
      if (!employee) return;
      await api('product_meta', { employee, product_key: keyOf(p), barcode: code }, true);
      toast('Штрихкод сохранён');
      await snapshot();
    } catch (e) { toast(e.message, true); }
  }

  const baseRenderHistory = renderHistory;
  renderHistory = function () {
    return baseRenderHistory();
  };

  const baseWireHistory = wireHistory;
  wireHistory = function () {
    baseWireHistory();
    document.querySelectorAll('.op').forEach(card => {
      const index = n(card.dataset.i);
      const op = S.operations[index];
      if (!op || op.operation_type === 'correction') return;
      const row = card.querySelector('.row');
      if (!row || row.querySelector('.correctOp')) return;
      const button = document.createElement('button');
      button.className = 'secondary correctOp';
      button.textContent = 'Коррекция';
      button.onclick = e => { e.stopPropagation(); correctOperationWeb(op); };
      row.appendChild(button);
    });
  };

  async function correctOperationWeb(op) {
    try {
      await api('authorize', {}, true);
      const employee = await ask('ФИО сотрудника');
      if (!employee) return;
      const reason = await ask('Причина корректировки');
      if (!reason) return;
      const options = (op.lines || []).map((l, i) => `<option value="${i}">${esc(l.product_name)}</option>`).join('');
      openModal(`<h2>Корректировка</h2><p class="muted">Исходная операция останется неизменной. Создаётся отдельная корректирующая запись.</p><select id="corrLine" class="input">${options}</select><input id="corrDelta" class="input" style="margin-top:8px" inputmode="numeric" placeholder="Изменение в базовой единице: -250 или +500"><div class="toolbar" style="margin-top:10px"><button id="corrSave">Создать</button><button id="corrCancel" class="secondary">Отмена</button></div>`);
      $('#corrCancel').onclick = closeModal;
      $('#corrSave').onclick = async () => {
        try {
          const line = op.lines[n($('#corrLine').value)];
          const delta = Number($('#corrDelta').value.replace('+',''));
          if (!Number.isFinite(delta) || delta === 0) throw Error('Введите ненулевую корректировку');
          const location = S.locations.find(x => x.is_primary) || S.locations[0];
          await api('correction', { employee, correction_of: op.id, reason, location_id: location?.id || null, lines: [{ product_key: line.product_key, delta_quantity: Math.trunc(delta) }] }, true);
          closeModal(); toast('Корректировка создана'); await snapshot();
        } catch (e) { toast(e.message, true); }
      };
    } catch (e) { toast(e.message, true); }
  }

  const baseRenderBuy = renderBuy;
  renderBuy = function () {
    let html = baseRenderBuy();
    if (!(S.purchase_requests || []).length) return html;
    html += `<div class="muted" style="margin-top:8px">Статус заявки можно изменить ниже.</div>`;
    html += (S.purchase_requests || []).map(r => `<div class="card noPrint"><div class="row"><div class="grow"><b>${esc((S.suppliers.find(s => s.id === r.supplier_id) || {}).name || 'Без поставщика')}</b><div class="muted">${dt(r.created_at)} • ${esc(r.status || 'draft')}</div></div><select class="input reqStatus" style="width:145px" data-id="${r.id}"><option value="draft" ${r.status==='draft'?'selected':''}>Черновик</option><option value="sent" ${r.status==='sent'?'selected':''}>Отправлена</option><option value="received" ${r.status==='received'?'selected':''}>Получена</option><option value="cancelled" ${r.status==='cancelled'?'selected':''}>Отменена</option></select></div></div>`).join('');
    return html;
  };

  const baseWireBuy = wireBuy;
  wireBuy = function () {
    baseWireBuy();
    document.querySelectorAll('.reqStatus').forEach(select => select.onchange = async () => {
      const old = (S.purchase_requests || []).find(r => r.id === select.dataset.id)?.status || 'draft';
      try {
        await api('authorize', {}, true);
        const employee = await ask('ФИО сотрудника');
        if (!employee) { select.value = old; return; }
        await api('purchase_request_status', { id: select.dataset.id, status: select.value, employee }, true);
        toast('Статус заявки обновлён'); await snapshot();
      } catch (e) { select.value = old; toast(e.message, true); }
    });
  };
})();
