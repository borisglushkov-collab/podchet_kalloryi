self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open("hub-v1").then((cache) => cache.addAll(["/hub/", "/hub/index.html", "/hub/styles.css", "/hub/app.js", "/hub/manifest.json", "/hub/icon.svg"]))
  );
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.pathname.startsWith("/api/")) return;
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
