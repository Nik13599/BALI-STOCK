'use strict';

const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('ios-web/ios-scanner-compat.js', 'utf8');
const numericBarcode = '0460123456789';

async function verifySecureWebClip() {
  let constructorConfig = null;
  let startConfig = null;
  let startCalls = 0;
  let decoded = '';
  let focusConstraints = null;

  function Html5Qrcode(elementId, config) {
    this.elementId = elementId;
    constructorConfig = config;
  }
  Html5Qrcode.prototype.start = function (_camera, config, success) {
    startCalls += 1;
    startConfig = config;
    success(numericBarcode, { decodedText: numericBarcode });
    return Promise.resolve('started');
  };

  const track = {
    getCapabilities() { return { focusMode: ['single-shot', 'continuous'] }; },
    applyConstraints(value) { focusConstraints = value; return Promise.resolve(); },
  };
  const video = { srcObject: { getVideoTracks() { return [track]; } } };
  const document = {
    createElement() { throw new Error('Live scanner must not create a photo input'); },
    getElementById(id) {
      if (id !== 'v14FlowReader') throw new Error(`Unexpected scanner element: ${id}`);
      return { querySelector(selector) { return selector === 'video' ? video : null; } };
    },
  };
  const formats = {
    QR_CODE: 0, CODE_39: 3, CODE_93: 4, CODE_128: 5, ITF: 9,
    EAN_13: 10, EAN_8: 11, UPC_A: 14, UPC_E: 15,
  };
  const context = {
    Html5Qrcode,
    Html5QrcodeSupportedFormats: formats,
    document,
    navigator: {
      userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 5,
      standalone: true,
      mediaDevices: { getUserMedia() { return Promise.resolve(); } },
    },
    location: { protocol: 'https:' },
    isSecureContext: true,
    console,
    Promise,
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context, { filename: 'ios-scanner-compat.js' });

  const scanner = new context.Html5Qrcode('v14FlowReader');
  const result = await scanner.start(
    { facingMode: 'environment' },
    { fps: 10, qrbox: { width: 250, height: 170 } },
    (value) => { decoded = value; },
    () => {}
  );
  await new Promise((resolve) => setImmediate(resolve));

  if (result !== 'started' || startCalls !== 1) throw new Error('Live camera stream was not started');
  if (decoded !== numericBarcode) throw new Error('Numeric barcode was not returned unchanged');
  if (!constructorConfig || constructorConfig.formatsToSupport.length !== 9) {
    throw new Error('Fast product barcode formats were not configured');
  }
  if (constructorConfig.useBarCodeDetectorIfSupported !== true) {
    throw new Error('Native BarcodeDetector acceleration was not enabled');
  }
  if (!startConfig || startConfig.fps !== 15 || startConfig.disableFlip !== true) {
    throw new Error('Fast live scan configuration was not applied');
  }
  const region = startConfig.qrbox(390, 300);
  if (region.width < 350 || region.height < 190 || region.width > 390 || region.height > 300) {
    throw new Error(`Unexpected scan region: ${JSON.stringify(region)}`);
  }
  if (!focusConstraints || focusConstraints.advanced[0].focusMode !== 'continuous') {
    throw new Error('Continuous autofocus was not requested');
  }
  if (source.includes("input.setAttribute('capture', 'environment')") || source.includes('scanFile(file, true)')) {
    throw new Error('Photo capture fallback is still present');
  }
}

async function verifyInsecurePageFailsClosed() {
  let startCalls = 0;
  function Html5Qrcode() {}
  Html5Qrcode.prototype.start = function () { startCalls += 1; return Promise.resolve(); };
  const context = {
    Html5Qrcode,
    Html5QrcodeSupportedFormats: { QR_CODE: 0 },
    document: { createElement() { throw new Error('Photo input must never be created'); } },
    navigator: {
      userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 5,
      standalone: true, mediaDevices: {},
    },
    location: { protocol: 'blob:' },
    isSecureContext: false,
    console,
    Promise,
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context, { filename: 'ios-scanner-compat.js' });
  const scanner = new context.Html5Qrcode('reader');
  let rejected = false;
  try {
    await scanner.start({}, {}, () => {}, () => {});
  } catch (error) {
    rejected = String(error).includes('HTTPS');
  }
  if (!rejected || startCalls !== 0) throw new Error('Insecure iPhone page did not fail closed');
}

(async () => {
  await verifySecureWebClip();
  await verifyInsecurePageFailsClosed();
  console.log(`iPhone live barcode scanner OK: ${numericBarcode}`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
