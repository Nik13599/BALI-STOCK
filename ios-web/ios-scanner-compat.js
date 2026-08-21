(function () {
  'use strict';

  window.__BALI_STOCK_IOS_SCANNER_COMPAT__ = '3.0';
  window.__BALI_STOCK_IOS_LIVE_SCANNER__ = true;

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

  function supportedProductFormats() {
    var formats = window.Html5QrcodeSupportedFormats;
    if (!formats) return [];
    return [
      formats.EAN_13,
      formats.EAN_8,
      formats.UPC_A,
      formats.UPC_E,
      formats.CODE_128,
      formats.CODE_39,
      formats.CODE_93,
      formats.ITF,
      formats.QR_CODE,
    ].filter(function (value, index, values) {
      return typeof value === 'number' && values.indexOf(value) === index;
    });
  }

  function optimizedConstructorConfig(configOrVerbose) {
    if (!isIos()) return configOrVerbose;
    var config = configOrVerbose && typeof configOrVerbose === 'object'
      ? Object.assign({}, configOrVerbose)
      : {};
    var formats = supportedProductFormats();
    if (formats.length) config.formatsToSupport = formats;
    config.useBarCodeDetectorIfSupported = true;
    return config;
  }

  function LiveScanner(elementId, configOrVerbose) {
    return new Scanner(elementId, optimizedConstructorConfig(configOrVerbose));
  }
  LiveScanner.prototype = Scanner.prototype;
  if (Object.setPrototypeOf) Object.setPrototypeOf(LiveScanner, Scanner);
  window.Html5Qrcode = LiveScanner;

  function scanRegion(viewfinderWidth, viewfinderHeight) {
    var width = Math.max(50, Math.floor(Number(viewfinderWidth || 0) * 0.92));
    var height = Math.max(50, Math.floor(Math.min(
      Number(viewfinderHeight || 0) * 0.70,
      width * 0.58
    )));
    return {
      width: Math.min(width, Math.max(50, Number(viewfinderWidth || width))),
      height: Math.min(height, Math.max(50, Number(viewfinderHeight || height))),
    };
  }

  function optimizedLiveConfig(configuration) {
    var config = Object.assign({}, configuration || {});
    config.fps = Math.max(15, Number(config.fps || 0));
    config.qrbox = scanRegion;
    config.disableFlip = true;
    return config;
  }

  function tuneContinuousFocus(scanner) {
    try {
      var root = document.getElementById(scanner.elementId);
      var video = root && root.querySelector ? root.querySelector('video') : null;
      var tracks = video && video.srcObject && video.srcObject.getVideoTracks
        ? video.srcObject.getVideoTracks()
        : [];
      var track = tracks && tracks[0];
      if (!track || !track.getCapabilities || !track.applyConstraints) return;
      var capabilities = track.getCapabilities();
      var modes = capabilities && capabilities.focusMode;
      if (!Array.isArray(modes) || modes.indexOf('continuous') < 0) return;
      Promise.resolve(track.applyConstraints({ advanced: [{ focusMode: 'continuous' }] })).catch(function () {});
    } catch (_) {}
  }

  function liveCameraAvailable() {
    var protocol = String(window.location && window.location.protocol ? window.location.protocol : '');
    return protocol === 'https:' &&
      window.isSecureContext !== false &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === 'function';
  }

  prototype.start = function (cameraIdOrConfig, configuration, success, scanError) {
    if (!isIos()) {
      return originalStart.call(this, cameraIdOrConfig, configuration, success, scanError);
    }
    if (!liveCameraAvailable()) {
      return Promise.reject(new Error('Live-сканер требует защищённое HTTPS-соединение и разрешение камеры.'));
    }
    var scanner = this;
    return Promise.resolve(originalStart.call(
      scanner,
      cameraIdOrConfig,
      optimizedLiveConfig(configuration),
      success,
      scanError
    )).then(function (result) {
      tuneContinuousFocus(scanner);
      return result;
    });
  };
})();
