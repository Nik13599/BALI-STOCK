(function () {
  'use strict';

  window.__BALI_STOCK_IOS_SCANNER_COMPAT__ = '2.0';

  var Scanner = window.Html5Qrcode;
  if (!Scanner || !Scanner.prototype || Scanner.prototype.__baliIosCompatInstalled) return;

  var prototype = Scanner.prototype;
  var originalStart = prototype.start;
  prototype.__baliIosCompatInstalled = true;

  function isIos() {
    var platform = String(navigator.platform || '');
    var userAgent = String(navigator.userAgent || '');
    return /iPhone|iPad|iPod/i.test(userAgent) ||
      (platform === 'MacIntel' && Number(navigator.maxTouchPoints || 0) > 1);
  }

  function needsNativeCapture() {
    var protocol = String(window.location && window.location.protocol ? window.location.protocol : '');
    return isIos() && (
      protocol.indexOf('blob') === 0 ||
      !window.isSecureContext ||
      !navigator.mediaDevices ||
      !navigator.mediaDevices.getUserMedia
    );
  }

  function nativeCapture(scanner, success, scanError) {
    var input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.setAttribute('aria-hidden', 'true');
    input.style.display = 'none';
    document.body.appendChild(input);

    function cleanup() {
      if (input.parentNode) input.parentNode.removeChild(input);
    }

    input.addEventListener('change', function () {
      var file = input.files && input.files[0];
      if (!file) {
        cleanup();
        return;
      }
      Promise.resolve(scanner.scanFile(file, true))
        .then(function (decoded) {
          cleanup();
          var text = String(decoded || '').trim();
          success(text, { decodedText: text });
        })
        .catch(function (error) {
          cleanup();
          if (typeof scanError === 'function') scanError(error);
          window.alert('Код на снимке не распознан. Поднесите камеру ближе и повторите сканирование.');
        });
    });

    // start() is called from the existing scan button, so the native picker
    // opens inside the same user gesture without adding buttons or icons.
    input.click();
    return Promise.resolve();
  }

  prototype.start = function (cameraIdOrConfig, configuration, success, scanError) {
    if (needsNativeCapture()) {
      return nativeCapture(this, success, scanError);
    }
    return originalStart.call(this, cameraIdOrConfig, configuration, success, scanError);
  };
})();
