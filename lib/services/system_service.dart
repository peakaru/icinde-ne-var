import 'package:flutter/services.dart';

/// Android tarafındaki küçük yardımcılar (MainActivity.kt, "icindenevar/system").
class SystemService {
  static const _channel = MethodChannel('icindenevar/system');

  /// Uygulamanın sistem ayarları sayfası (izinler buradan açılır).
  static Future<bool> openAppSettings() => _call('openAppSettings');

  /// Bağlantıyı tarayıcıda açar (yalnızca https).
  static Future<bool> openUrl(String url) => _call('openUrl', {'url': url});

  static Future<bool> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false; // Android dışı platform
    }
  }
}
