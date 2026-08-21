const fs = require('fs');
const { chromium } = require('playwright');

const source = fs.readFileSync('ios-web/ios-persistence-v109.js', 'utf8');

async function outbox(page) {
  return page.evaluate(async () => {
    const request = indexedDB.open('bali-stock-ios-persistence', 1);
    const db = await new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    return new Promise((resolve, reject) => {
      const read = db.transaction('outbox', 'readonly').objectStore('outbox').getAll();
      read.onsuccess = () => resolve(read.result || []);
      read.onerror = () => reject(read.error);
    });
  });
}

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.BALI_CHROME || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
  });
  const page = await browser.newPage();
  const received = [];
  await page.route('https://example.test/', route => route.fulfill({
    status: 200,
    contentType: 'text/html',
    body: '<!doctype html><div id="sync"></div><span id="v14Pending"></span>'
  }));
  await page.route('https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-sync-api', async route => {
    const body = route.request().postDataJSON();
    received.push(body);
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        id: body.action === 'supplier_upsert' ? 'server-supplier' : undefined,
        snapshot: {
          version: received.length,
          products: [{name: 'Test', category_name: 'Test', stock_unit: 'pcs', package_size: 1,
            minimum_amount: body.minimum_amount || 0, balance: {quantity_base: 0, initialized: true}}],
          operations: [], drafts: [], suppliers: [], locations: []
        }
      })
    });
  });
  await page.goto('https://example.test/');
  await page.addScriptTag({content: `
    var KEY='test-key';
    var S={version:0,products:[{name:'Test',category_name:'Test',stock_unit:'pcs',package_size:1,minimum_amount:0,balance:{quantity_base:0,initialized:true}}],operations:[],drafts:[],suppliers:[],locations:[]};
    var keyOf=function(p){return p.name.toLowerCase()+'|'+p.stock_unit+'|'+p.package_size};
    var render=function(){};
    var api=async function(){throw new TypeError('Failed to fetch')};
    var snapshot=async function(){return S};
  `});
  await page.addScriptTag({content: source});
  await page.evaluate(() => Object.defineProperty(navigator, 'onLine', {configurable: true, value: false}));

  await page.evaluate(() => api('product_meta', {product_key:'test|pcs|1', minimum_amount:3}, true));
  await page.evaluate(() => api('product_meta', {product_key:'test|pcs|1', minimum_amount:7}, true));
  let queued = await outbox(page);
  if (queued.length !== 1 || queued[0].payload.minimum_amount !== 7) throw new Error('product metadata was not coalesced');
  const localMinimum = await page.evaluate(() => S.products[0].minimum_amount);
  if (localMinimum !== 7) throw new Error('offline product change was not visible locally');

  const draft = {employee:'Tester', status:'in_progress', started_at:'2026-08-21T00:00:00.000Z', active_seconds:1,
    filled_count:0,total_count:1,payload:{lines:[]}};
  await page.evaluate(body => api('draft_sync', body, true), draft);
  await page.evaluate(body => api('draft_sync', {...body, active_seconds:2}, true), draft);
  queued = await outbox(page);
  if (queued.filter(x => x.action === 'draft_sync').length !== 1) throw new Error('draft updates were not coalesced');
  await page.evaluate(body => api('draft_delete', {employee:body.employee, started_at:body.started_at}, true), draft);
  queued = await outbox(page);
  if (queued.some(x => x.action === 'draft_sync')) throw new Error('deleted draft remained queued for recreation');

  await page.evaluate(() => Object.defineProperty(navigator, 'onLine', {configurable: true, value: true}));
  await page.evaluate(() => window.baliFlushPersistence());
  queued = await outbox(page);
  if (queued.length !== 0 || received.length < 2) throw new Error('durable queue did not flush');

  await page.evaluate(() => Object.defineProperty(navigator, 'onLine', {configurable: true, value: false}));
  const pendingSupplier = await page.evaluate(async () => {
    const supplier = await api('supplier_upsert', {id:null,name:'Offline supplier'}, true);
    await api('supplier_link', {product_key:'test|pcs|1',supplier_id:supplier.id,is_primary:true}, true);
    return supplier.id;
  });
  if (!String(pendingSupplier).startsWith('pending:')) throw new Error('offline supplier did not receive a durable local id');
  await page.evaluate(() => Object.defineProperty(navigator, 'onLine', {configurable: true, value: true}));
  await page.evaluate(() => window.baliFlushPersistence());
  const supplierLink = received.filter(x => x.action === 'supplier_link').pop();
  if (!supplierLink || supplierLink.supplier_id !== 'server-supplier') throw new Error('dependent supplier link was not remapped');

  await page.evaluate(() => Object.defineProperty(navigator, 'onLine', {configurable: true, value: false}));
  const delivery = await page.evaluate(async () => {
    const upload = await api('invoice_attachment_upload', {file_name:'invoice.jpg',mime_type:'image/jpeg',data_base64:'AQ=='}, true);
    const scan = await api('invoice_scan_save', {employee:'Tester',raw_text:'invoice',lines:[]}, true);
    return api('delivery', {employee:'Tester',attachment_url:upload.path,metadata:{invoice_scan_id:scan.id},lines:[]}, true);
  });
  if (!delivery.queued) throw new Error('offline delivery bundle was not retained');
  queued = await outbox(page);
  if (queued.length !== 1 || queued[0].action !== 'delivery_bundle') throw new Error('attachment and delivery were not bundled');

  await browser.close();
  console.log('iPhone durable persistence queue OK');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
