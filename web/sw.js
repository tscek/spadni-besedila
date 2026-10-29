// Service worker za delo brez interneta.
// Vsako datoteko aplikacije (tudi pisave in CanvasKit z Googlovih strežnikov) ob uporabi shrani;
// najprej poskusi z interneta (da je aplikacija vedno sveža), brez povezave vrne shranjeno.
// Klici skripte in prijave gredo vedno mimo, podatki pesmi so shranjeni v aplikaciji sami (IndexedDB).
const SHRAMBA = 'spadni-besedila-v1';
const MIMO = ['script.google.com', 'script.googleusercontent.com', 'accounts.google.com', 'oauth2.googleapis.com'];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (e) => {
  const zahteva = e.request;
  if (zahteva.method !== 'GET') return;
  const url = new URL(zahteva.url);
  if (MIMO.some((h) => url.hostname === h || url.hostname.endsWith('.' + h))) return;
  if (url.protocol !== 'https:' && url.hostname !== 'localhost') return;

  e.respondWith((async () => {
    const shramba = await caches.open(SHRAMBA);
    try {
      const odgovor = await fetch(zahteva);
      if (odgovor.ok || odgovor.type === 'opaque') shramba.put(zahteva, odgovor.clone());
      return odgovor;
    } catch (napaka) {
      const shranjen = await shramba.match(zahteva, { ignoreSearch: url.origin === self.location.origin });
      if (shranjen) return shranjen;
      // Nova stran brez interneta: vrni začetno stran aplikacije.
      if (zahteva.mode === 'navigate') {
        const zacetna = await shramba.match('./', { ignoreSearch: true }) || await shramba.match('index.html');
        if (zacetna) return zacetna;
      }
      throw napaka;
    }
  })());
});
