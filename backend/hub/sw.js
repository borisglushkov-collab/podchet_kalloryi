const params = new URL(self.location.href).searchParams;
const VER = params.get("v") || "dev";
const CACHE = `hub-${VER}`;

const SHELL = [
  "/hub/",
  "/hub/index.html",
  `/hub/styles.css?v=${encodeURIComponent(VER)}`,
  `/hub/js/main.js?v=${encodeURIComponent(VER)}`,
  `/hub/js/logic.js?v=${encodeURIComponent(VER)}`,
  `/hub/js/api.js?v=${encodeURIComponent(VER)}`,
  `/hub/js/state.js?v=${encodeURIComponent(VER)}`,
  `/hub/js/ui.js?v=${encodeURIComponent(VER)}`,
  `/hub/js/render.js?v=${encodeURIComponent(VER)}`,
  "/hub/manifest.json",
  "/hub/icon.svg",
];

self.addEventListener("install", (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(
        SHELL.map((url) => cache.add(url).catch(() => undefined)),
      ),
    ),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))),
  );
  self.clients.claim();
});

function isShell(url) {
  return (
    url.pathname === "/hub/" ||
    url.pathname.endsWith(".js") ||
    url.pathname.endsWith(".css") ||
    url.pathname.endsWith(".html")
  );
}

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.pathname.startsWith("/api/")) return;
  if (event.request.method !== "GET") return;

  if (isShell(url)) {
    event.respondWith(
      fetch(event.request, { cache: "no-store" })
        .then((resp) => {
          if (resp.ok) {
            const copy = resp.clone();
            caches.open(CACHE).then((cache) => cache.put(event.request, copy));
          }
          return resp;
        })
        .catch(async () => {
          const cached = await caches.match(event.request);
          if (cached) return cached;
          if (!url.search) {
            const verHit = await caches.match(`${url.pathname}?v=${encodeURIComponent(VER)}`);
            if (verHit) return verHit;
          }
          return caches.match(url.pathname);
        }),
    );
    return;
  }

  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
