const CACHE = 'bali-stock-v13-shell-1';
const SHELL = ['./', './index.html', './manifest.webmanifest', './bali_stock_logo.png'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  );
});
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.includes('supabase.co')) return;

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then(r=>{
        const copy=r.clone(); caches.open(CACHE).then(c=>c.put('./index.html',copy)); return r;
      }).catch(()=>caches.match('./index.html'))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(cached => {
      const network = fetch(req).then(r=>{
        if (r && (r.ok || r.type === 'opaque')) {
          const copy = r.clone();
          caches.open(CACHE).then(c=>c.put(req,copy));
        }
        return r;
      }).catch(()=>cached);
      return cached || network;
    })
  );
});
