// Service worker for Web Push (put in /web, next to index.html)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data.json(); } catch (_) {}

  const isEmergency = (d.tag || '').startsWith('emergency-');

  const options = {
    body: d.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    requireInteraction: true,
    vibrate: isEmergency ? [300, 100, 300, 100, 300] : [200, 100, 200],
    data: d,
  };

  // renotify hanya sah jika ada tag (kalau tak, showNotification gagal senyap)
  if (d.tag) {
    options.tag = d.tag;
    options.renotify = true;
  }

  // iOS requires a visible notification for every push.
  event.waitUntil(
    self.registration.showNotification(
      d.title || (isEmergency ? 'Kecemasan' : 'Peringatan Ubat'),
      options
    )
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const d = event.notification.data || {};

  event.waitUntil(
    (async () => {
      // Alert kecemasan: buka lokasi pesakit (hanya link Google Maps dibenarkan)
      if (typeof d.url === 'string' && d.url.startsWith('https://maps.google.com/')) {
        return self.clients.openWindow(d.url);
      }
      // Peringatan ubat: fokus tab app yang sedia ada, atau buka baru
      const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const c of list) if ('focus' in c) return c.focus();
      return self.clients.openWindow('./');
    })()
  );
});