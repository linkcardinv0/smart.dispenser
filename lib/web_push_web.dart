import 'dart:convert';
import 'dart:js_interop';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Paste the PUBLIC key from `npx web-push generate-vapid-keys`.
const String kWebVapidPublicKey = 'BHXu_J2VCN1C7l_gFGzx4n4waFKVp1JF7evTphVuWW6PC8GfjMg1yUmr4NnUlOwadwfq2pZu3L2yagYCeuSQe7E';

@JS('smartPush.subscribe')
external JSPromise _subscribe(JSString vapidKey);

@JS('smartPush.existing')
external JSPromise _existing();

Future<void> _save(String subJson) async {
  final m = jsonDecode(subJson) as Map<String, dynamic>;
  final keys = m['keys'] as Map<String, dynamic>;
  await Supabase.instance.client.rpc('save_push_subscription', params: {
    'p_endpoint': m['endpoint'],
    'p_p256dh': keys['p256dh'],
    'p_auth': keys['auth'],
  });
}

/// Call directly from a button tap (no `await` before it).
Future<bool> enableWebPush() async {
  try {
    final res = await _subscribe(kWebVapidPublicKey.toJS).toDart;
    if (res == null) return false;
    await _save((res as JSString).toDart);
    return true;
  } catch (_) {
    return false;
  }
}

/// Call after login: re-links this device to the current user (no prompt).
Future<void> syncWebPushSubscription() async {
  try {
    final res = await _existing().toDart;
    if (res != null) await _save((res as JSString).toDart);
  } catch (_) {}
}