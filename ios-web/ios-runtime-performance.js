(function () {
  'use strict';

  window.__BALI_STOCK_IOS_RUNTIME_PERFORMANCE__ = '1.0';
  var polling = false;
  var lastVersion = Number(S && S.version ? S.version : 0);

  window.baliPollSnapshotVersion = async function () {
    if (polling || document.hidden || navigator.onLine === false) return;
    polling = true;
    try {
      var response = await fetch(API + '?action=version', {
        headers: { apikey: KEY, Accept: 'application/json' },
        cache: 'no-store'
      });
      var payload = await response.json();
      if (!response.ok) throw new Error(payload && payload.error ? payload.error : String(response.status));
      var version = Number(payload && payload.version ? payload.version : 0);
      if (!lastVersion) lastVersion = Number(S && S.version ? S.version : version);
      if (version && version !== lastVersion) {
        await snapshot();
        lastVersion = Number(S && S.version ? S.version : version);
      }
    } catch (_) {
      // Keep the current local snapshot visible; the next lightweight tick retries.
    } finally {
      polling = false;
    }
  };

  window.addEventListener('online', window.baliPollSnapshotVersion);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) window.baliPollSnapshotVersion();
  });
})();
