// Service worker do app Funil Alinha Face.
// Sempre busca a versão mais nova na internet; o cache só serve se a conexão cair.
// Nunca guarda dados de pacientes: chamadas ao Supabase passam direto.
const CACHE = "funil-v22";
const BASE = ["./", "index.html", "painel.html", "medico.html", "voucher.html", "auth.js", "whats.js", "recados.js", "agenda.js", "tele.js", "sala.html", "config.js", "base.css", "manifest.webmanifest", "icones/icone-192.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(BASE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;   // Supabase, fontes, CDN: direto
  e.respondWith(
    fetch(e.request).then(r => {
      if (r.ok) { const copia = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copia)); }
      return r;
    }).catch(() => caches.match(e.request, { ignoreSearch: true }))
  );
});
