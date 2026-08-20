(function () {
  'use strict';
  window.__BALI_STOCK_V15_COMPAT__ = '15.1';

  var CLIENT_API = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-client-api';
  var originalGetElementById = document.getElementById.bind(document);
  var aliases = {
    v14Photo: 'v14pcPhoto',
    v14Edit: 'v14pcEdit',
    v14Spot: 'v14pcStocktake'
  };

  document.getElementById = function (id) {
    var direct = originalGetElementById(id);
    if (direct) return direct;
    var alias = aliases[id];
    return alias ? originalGetElementById(alias) : null;
  };

  function clientKey() {
    try {
      if (typeof KEY !== 'undefined' && KEY) return String(KEY);
    } catch (_) {}
    return '';
  }

  async function fallbackSnapshot() {
    var key = clientKey();
    if (!key) throw Error('Ключ подключения BALI STOCK не загружен. Перезапустите приложение.');
    var response = await fetch(CLIENT_API + '?action=snapshot&compat=' + Date.now(), {
      method: 'GET',
      cache: 'no-store',
      headers: { apikey: key, Accept: 'application/json' }
    });
    var data = await response.json().catch(function () { return {}; });
    if (!response.ok) throw Error(data.error || ('snapshot HTTP ' + response.status));
    var next = data && data.snapshot ? data.snapshot : data;
    if (!next || typeof next !== 'object') throw Error('Сервер вернул пустой снимок склада.');
    try {
      S = next;
    } catch (_) {
      window.S = next;
    }
    return next;
  }

  var hasBaseSnapshot = false;
  try {
    hasBaseSnapshot = typeof snapshot === 'function';
  } catch (_) {
    hasBaseSnapshot = false;
  }

  if (!hasBaseSnapshot) {
    window.snapshot = fallbackSnapshot;
    window.__BALI_STOCK_SNAPSHOT_FALLBACK__ = true;
  } else {
    window.__BALI_STOCK_SNAPSHOT_FALLBACK__ = false;
  }

  window.baliRefreshSnapshot = async function () {
    var active = null;
    try {
      active = typeof snapshot === 'function' ? snapshot : null;
    } catch (_) {}
    if (active && active !== window.baliRefreshSnapshot) return active();
    return fallbackSnapshot();
  };

  var iconPaths = {
    home: '<path d="M3 9.2 12 3.7l9 5.5V20H3Z"/><path d="M7 11h10v9M7 14h10M7 17h10"/>',
    stock: '<rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M4.5 10h15M4.5 15h15"/><rect x="6" y="6" width="4" height="3"/><rect x="13.5" y="11.5" width="4" height="2.5"/><rect x="8.5" y="16.5" width="5" height="2.5"/>',
    count: '<rect x="5" y="4.5" width="14" height="16" rx="2"/><rect x="8.5" y="2.8" width="7" height="3.6" rx="1"/><path d="M8 9h8M8 14l2.7 2.5 6.1-5.5"/>',
    buy: '<path d="M3 5h2.5l1.7 10.2h10.3L20 8H6"/><circle cx="9" cy="19" r="1.2"/><circle cx="17" cy="19" r="1.2"/>',
    delivery: '<rect x="2.5" y="7" width="11.5" height="9" rx="1.4"/><path d="M14 10h4.2L21 13v3h-7Z"/><path d="M16.2 11.1h2l1.6 1.9M9 18h7"/><circle cx="7" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>',
    control: '<path d="M8 3.2h8L21 8v8l-5 4.8H8L3 16V8Z"/><circle cx="12" cy="12" r="3.3"/><path d="M12 5.8v2.4M12 15.8v2.4M5.8 12h2.4M15.8 12h2.4"/>'
  };

  function navSvg(path) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + path + '</svg>';
  }

  function ensureNavCss() {
    if (originalGetElementById('baliCompatNavCss')) return;
    var style = document.createElement('style');
    style.id = 'baliCompatNavCss';
    style.textContent = '.bali-custom-nav-icon{display:grid!important;place-items:center!important;height:24px!important;margin:0 auto 4px!important;font-size:0!important;line-height:0!important}.bali-custom-nav-icon svg{width:23px;height:23px;display:block}.bottom button.active .bali-custom-nav-icon,nav button.active .bali-custom-nav-icon{color:#39ff6a!important}';
    document.head.appendChild(style);
  }

  function applyNavIcons() {
    ensureNavCss();
    document.querySelectorAll('nav button[data-tab], .bottom button[data-tab]').forEach(function (button) {
      var path = iconPaths[button.getAttribute('data-tab')];
      var holder = button.querySelector('b');
      if (!path || !holder) return;
      if (holder.getAttribute('data-bali-custom-icon') === '1') return;
      holder.classList.add('bali-custom-nav-icon');
      holder.setAttribute('data-bali-custom-icon', '1');
      holder.innerHTML = navSvg(path);
    });
  }

  function bootNavIcons() {
    applyNavIcons();
    setTimeout(applyNavIcons, 80);
    setTimeout(applyNavIcons, 350);
    var root = document.body || document.documentElement;
    if (!root || typeof MutationObserver === 'undefined') return;
    var observer = new MutationObserver(function () { applyNavIcons(); });
    observer.observe(root, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootNavIcons, { once: true });
  } else {
    bootNavIcons();
  }
})();
