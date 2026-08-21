(function () {
  'use strict';

  window.__BALI_STOCK_IOS_SCANNER_COMPAT__ = '1.0';

  var Scanner = window.Html5Qrcode;
  if (!Scanner || !Scanner.prototype || Scanner.prototype.__baliIosCompatInstalled) return;

  var prototype = Scanner.prototype;
  var originalStart = prototype.start;
  var originalStop = prototype.stop;
  prototype.__baliIosCompatInstalled = true;

  function errorText(error) {
    var name = String(error && error.name ? error.name : '');
    if (!window.isSecureContext || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      return 'Live-камера недоступна в этом режиме iPhone. Сфотографируйте код системной камерой.';
    }
    if (name === 'NotAllowedError' || name === 'SecurityError') {
      return 'Доступ к камере запрещён. Разрешите камеру для сайта либо сфотографируйте код.';
    }
    if (name === 'NotFoundError' || name === 'OverconstrainedError') {
      return 'Задняя камера не найдена. Можно сфотографировать код или ввести его вручную.';
    }
    if (name === 'NotReadableError' || name === 'AbortError') {
      return 'iPhone не запустил видеопоток. Закройте другие приложения с камерой или сфотографируйте код.';
    }
    return 'Live-сканирование не запустилось. Сфотографируйте QR-код или штрихкод.';
  }

  function removeFallback(scanner) {
    var current = document.querySelector('[data-bali-scanner-for="' + scanner.elementId + '"]');
    if (current && current.parentNode) current.parentNode.removeChild(current);
  }

  function addPhotoFallback(scanner, success, error) {
    var reader = document.getElementById(scanner.elementId);
    if (!reader || typeof success !== 'function') return;

    removeFallback(scanner);
    var panel = document.createElement('div');
    panel.setAttribute('data-bali-scanner-for', scanner.elementId);
    panel.style.cssText = 'margin-top:10px;padding:12px;border:1px solid #294233;border-radius:14px;background:#101c15';

    var status = document.createElement('div');
    status.className = 'muted';
    status.style.cssText = 'margin-bottom:10px;line-height:1.4';
    status.textContent = error ? errorText(error) : 'Если live-камера не распознаёт код, сделайте один снимок.';
    panel.appendChild(status);

    var label = document.createElement('label');
    label.style.cssText = 'display:block;width:100%;box-sizing:border-box;padding:12px 14px;border-radius:12px;background:#183522;color:#39ff6a;text-align:center;font-weight:900;cursor:pointer';
    label.textContent = 'СФОТОГРАФИРОВАТЬ КОД';

    var input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.style.display = 'none';
    label.appendChild(input);
    panel.appendChild(label);
    reader.insertAdjacentElement('afterend', panel);

    input.addEventListener('change', function () {
      var file = input.files && input.files[0];
      if (!file) return;
      status.textContent = 'Распознаю код на снимке…';
      label.style.pointerEvents = 'none';
      label.style.opacity = '.65';

      var stopped;
      try {
        stopped = originalStop.call(scanner);
      } catch (_) {
        stopped = Promise.resolve();
      }
      Promise.resolve(stopped)
        .catch(function () {})
        .then(function () {
          try { scanner.clear(); } catch (_) {}
          return scanner.scanFile(file, true);
        })
        .then(function (decoded) {
          removeFallback(scanner);
          success(String(decoded || '').trim(), { decodedText: String(decoded || '').trim() });
        })
        .catch(function () {
          status.textContent = 'Код на снимке не распознан. Поднесите камеру ближе и повторите.';
          label.style.pointerEvents = '';
          label.style.opacity = '';
          input.value = '';
        });
    });
  }

  prototype.start = function (cameraIdOrConfig, configuration, success, scanError) {
    var scanner = this;
    if (!window.isSecureContext || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      addPhotoFallback(scanner, success, new Error('INSECURE_CAMERA_CONTEXT'));
      return Promise.resolve();
    }

    var started;
    try {
      started = originalStart.call(scanner, cameraIdOrConfig, configuration, success, scanError);
    } catch (error) {
      addPhotoFallback(scanner, success, error);
      return Promise.resolve();
    }

    return Promise.resolve(started)
      .then(function (value) {
        addPhotoFallback(scanner, success, null);
        return value;
      })
      .catch(function (error) {
        addPhotoFallback(scanner, success, error);
        return undefined;
      });
  };
})();
