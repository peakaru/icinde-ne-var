import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'database_service.dart';

/// Yayımlanmış yeni sürüm
class UpdateInfo {
  final String version; // "1.3.0"
  final String url;     // GitHub sürüm sayfası
  const UpdateInfo(this.version, this.url);
}

/// APK Play Store dışında dağıtıldığı için güncelleme kendiliğinden gelmez.
/// Açılışta (günde en fazla bir kez) GitHub'daki son sürüme bakılır; yalnızca
/// sürüm numarası okunur, istekte ürün ya da kişisel veri gönderilmez.
class UpdateService {
  static const _latestRelease =
      'https://api.github.com/repos/peakaru/icinde-ne-var/releases/latest';
  static const _releasePagePrefix = 'https://github.com/peakaru/icinde-ne-var/releases/';
  static const _checkEvery = Duration(hours: 24);

  /// HTTP istemcisi — testlerde `MockClient` ile değiştirilir.
  @visibleForTesting
  static http.Client client = http.Client();

  /// Kurulu sürümden yeni bir sürüm varsa ve kullanıcı onu kapatmadıysa döner.
  static Future<UpdateInfo?> check() async {
    try {
      final installed = (await PackageInfo.fromPlatform()).version;
      final latest = await _latest();
      if (latest == null || compareVersions(latest.version, installed) <= 0) return null;
      if (await DatabaseService.getSetting('update_dismissed') == latest.version) return null;
      return latest;
    } catch (e) {
      debugPrint('Sürüm kontrolü yapılamadı: $e');
      return null;
    }
  }

  /// Bu sürüm için kartı bir daha gösterme
  static Future<void> dismiss(String version) =>
      DatabaseService.setSetting('update_dismissed', version);

  /// Son sürüm: 24 saatte bir GitHub'dan, arada kayıtlı sonuçtan
  static Future<UpdateInfo?> _latest() async {
    final checkedAt = DateTime.tryParse(await DatabaseService.getSetting('update_checked_at') ?? '');
    final cachedVersion = await DatabaseService.getSetting('update_latest_version');
    final cachedUrl = await DatabaseService.getSetting('update_latest_url');
    final cached = (cachedVersion != null && cachedUrl != null)
        ? UpdateInfo(cachedVersion, cachedUrl)
        : null;
    if (checkedAt != null && DateTime.now().difference(checkedAt) < _checkEvery) return cached;

    final Object? body;
    try {
      final res = await client
          .get(Uri.parse(_latestRelease), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      await DatabaseService.setSetting('update_checked_at', DateTime.now().toIso8601String());
      if (res.statusCode != 200) return cached;
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return cached; // internet yok ya da GitHub yanıt vermedi
    }
    final info = parseRelease(body);
    if (info == null) return cached;
    await DatabaseService.setSetting('update_latest_version', info.version);
    await DatabaseService.setSetting('update_latest_url', info.url);
    return info;
  }

  /// GitHub yanıtından sürüm ve sayfa adresi. Taslak/ön sürümler ve
  /// beklenmeyen adresler yok sayılır.
  @visibleForTesting
  static UpdateInfo? parseRelease(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final url = json['html_url'];
    if (tag is! String || url is! String || !url.startsWith(_releasePagePrefix)) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) return null;
    return UpdateInfo(version, url);
  }

  /// "1.10.0" > "1.9.2"; eksik parçalar 0 sayılır ("1.3" == "1.3.0").
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
