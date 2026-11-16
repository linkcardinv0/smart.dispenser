// Add to web/index.html inside <head>:  <script src="push.js"></script>
(function () {
  function b64ToUint8(b64) {
    const pad = '='.repeat((4 - (b64.length % 4)) % 4);
    const raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(raw, (c) => c.charCodeAt(0));
  }
  const supported = () =>
    'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

  window.smartPush = {
    // MUST be called straight from a tap (iOS rule). Returns subscription JSON or null.
    subscribe: async function (vapidKey) {
      if (!supported()) return null;
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') return null;
      const reg = await navigator.serviceWorker.register('push-sw.js');
      await navigator.serviceWorker.ready;
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: b64ToUint8(vapidKey),
        });
      }
      return JSON.stringify(sub);
    },
    // No prompt: returns existing subscription JSON (if already allowed) or null.
    existing: async function () {
      if (!supported() || Notification.permission !== 'granted') return null;
      const reg = await navigator.serviceWorker.getRegistration('push-sw.js') ||
                  await navigator.serviceWorker.getRegistration();
      if (!reg) return null;
      const sub = await reg.pushManager.getSubscription();
      return sub ? JSON.stringify(sub) : null;
    },
  };
})();
