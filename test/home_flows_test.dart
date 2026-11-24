import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icinde_ne_var/screens/home_screen.dart';
import 'package:icinde_ne_var/services/api_service.dart';
import 'package:icinde_ne_var/services/database_service.dart';
import 'package:icinde_ne_var/services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

const _updateKeys = ['update_checked_at', 'update_latest_version', 'update_latest_url', 'update_dismissed'];

Future<void> _resetUpdateSettings() async {
  for (final k in _updateKeys) {
    await DatabaseService.setSetting(k, '');
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PackageInfo.setMockInitialValues(
        appName: 'İçinde Ne Var?', packageName: 'com.peakaru.icindenevar',
        version: '1.2.0', buildNumber: '3', buildSignature: '');
    await DatabaseService.setSetting('lang', 'tr');
  });
  tearDownAll(_resetUpdateSettings);

  group('Ana ekran', () {
    const wake = 'Sunucu uyanıyor';

    setUp(() async {
      // Ana ekran açılışta sürüm kontrolü yapar; ağa çıkmasın
      UpdateService.client = MockClient((_) async => http.Response('', 404));
      await _resetUpdateSettings();
    });

    Future<void> openHome(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      // Açılıştaki veritabanı okumaları (dil, son bakılanlar, sürüm kontrolü)
      // gerçek zamanlı çalışır; her biri için bir tur bekleyip yeniden çiz
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    /// Arama yanıtı [delay] sonra gelir (uyuyan sunucu)
    void slowSearch(Duration delay) {
      ApiService.client = MockClient((_) async {
        await Future<void>.delayed(delay);
        return _json({'results': []}, 200);
      });
    }

    testWidgets('uyuyan sunucu: uyarı 4 sn sonra çıkar, yanıt gelince kalkar', (tester) async {
      slowSearch(const Duration(seconds: 8));
      await openHome(tester);
      await tester.enterText(find.byType(TextField), 'gofret');
      await tester.pump(const Duration(milliseconds: 500)); // arama gecikmesi
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining(wake), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500)); // bildirim animasyonu
      expect(find.textContaining(wake), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // yanıt geldi
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(wake), findsNothing);
    });

    testWidgets('arama kutusu silinse de yanıt gelince uyarı kalkar', (tester) async {
      slowSearch(const Duration(seconds: 8));
      await openHome(tester);
      await tester.enterText(find.byType(TextField), 'gofret');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), ''); // yoldaki arama geçersiz
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 4)); // yanıt geldi
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(wake), findsNothing);
    });

    testWidgets('hızlı yanıtta uyarı hiç çıkmaz', (tester) async {
      slowSearch(const Duration(seconds: 1));
      await openHome(tester);
      await tester.enterText(find.byType(TextField), 'gofret');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining(wake), findsNothing);
    });

    testWidgets('bulunamayan barkod: açıklama sayfası açılır, kaydedildi denmez', (tester) async {
      ApiService.client = MockClient((_) async => _json({'detail': 'Ürün bulunamadı'}, 404));
      await openHome(tester);
      await tester.enterText(find.byType(TextField), '8690000000017');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 500)); // sayfa animasyonu
      expect(find.text('Bu ürün veritabanımızda yok'), findsOneWidget);
      expect(find.text('8690000000017'), findsWidgets);
      expect(find.text('İsimle ara'), findsOneWidget);
      expect(find.text('Tekrar tara'), findsOneWidget);
      expect(find.textContaining('kaydedildi'), findsNothing);
      expect(find.textContaining('kaydettik'), findsNothing);

      // Barkod kopyalanınca sayfanın içinde onay görünür
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.bySemanticsLabel(RegExp('^Barkodu kopyala')));
      await tester.pump();
      expect(copied, ['8690000000017']);
      expect(find.text('kopyalandı'), findsOneWidget);

      // "İsimle ara" sayfayı kapatır
      await tester.tap(find.text('İsimle ara'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // kapanma animasyonu
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Bu ürün veritabanımızda yok'), findsNothing);
    });

    testWidgets('yeni sürüm varsa ana ekranda kart çıkar, kapatılınca gider', (tester) async {
      UpdateService.client = MockClient((_) async => _json({
            'tag_name': 'v1.3.0',
            'html_url': 'https://github.com/peakaru/icinde-ne-var/releases/tag/v1.3.0',
          }, 200));
      await openHome(tester);
      expect(find.text('Yeni sürüm var: 1.3.0'), findsOneWidget);
      await tester.tap(find.byTooltip('Bu sürümü gösterme'));
      await tester.pump();
      expect(find.text('Yeni sürüm var: 1.3.0'), findsNothing);
    });
  });

  group('Sürüm kontrolü', () {
    const page = 'https://github.com/peakaru/icinde-ne-var/releases/tag/v1.3.0';
    setUp(_resetUpdateSettings);

    test('yeni sürüm bulunur, günde bir kez sorulur, kapatılınca gösterilmez', () async {
      var calls = 0;
      UpdateService.client = MockClient((req) async {
        calls++;
        expect(req.url.toString(), 'https://api.github.com/repos/peakaru/icinde-ne-var/releases/latest');
        return _json({'tag_name': 'v1.3.0', 'html_url': page}, 200);
      });
      expect((await UpdateService.check())?.version, '1.3.0');
      expect((await UpdateService.check())?.url, page); // 24 saat dolmadı: kayıttan
      expect(calls, 1);
      await UpdateService.dismiss('1.3.0');
      expect(await UpdateService.check(), isNull);
    });

    test('kurulu sürüm en yeniyse kart çıkmaz', () async {
      UpdateService.client = MockClient((_) async => _json({
            'tag_name': 'v1.2.0',
            'html_url': 'https://github.com/peakaru/icinde-ne-var/releases/tag/v1.2.0',
          }, 200));
      expect(await UpdateService.check(), isNull);
    });

    test('internet yoksa sessizce geçer', () async {
      UpdateService.client = MockClient((_) async => throw http.ClientException('Failed host lookup'));
      expect(await UpdateService.check(), isNull);
    });
  });
}
