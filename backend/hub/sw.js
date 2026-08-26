const params = new URL(self.location.href).searchParams;
const VER = params.get("v") || "dev";
const CACHE = `hub-${VER}`;

const SHELL = [
  "/hub/",
  "/hub/index.html",
  `/hub/styles.css?v=${encodeURIComponent(VER)}`,
  `/hub/js/main.js?v=${encodeURIComponent(VER)}`,
  "/hub/js/logic.js",
  "/hub/js/api.js",
  "/hub/js/state.js",
  "/hub/js/ui.js",
  "/hub/js/render.js",
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
      fetch(event.request)
        .then((resp) => {
          if (resp.ok) {
            const copy = resp.clone();
            caches.open(CACHE).then((cache) => cache.put(event.request, copy));
          }
          return resp;
        })
        .catch(() =>
          caches.match(event.request).then((cached) => cached || caches.match(url.pathname)),
        ),
    );
    return;
  }

  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
