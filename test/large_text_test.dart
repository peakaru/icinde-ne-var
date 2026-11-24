import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icinde_ne_var/models/product.dart';
import 'package:icinde_ne_var/screens/history_screen.dart';
import 'package:icinde_ne_var/screens/home_screen.dart';
import 'package:icinde_ne_var/screens/product_detail_screen.dart';
import 'package:icinde_ne_var/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Büyük yazı tipi (erişilebilirlik ayarı) ve dar ekranda taşma olmamalı.
/// Taşma (RenderFlex overflow) testte hata olarak yakalanır.
void main() {
  final full = Product(
    barcode: '8690504135913',
    productName: 'Ülker Çikolatalı Gofret Fındık Kremalı Uzun Ürün Adı 36 G',
    brand: 'Ülker',
    nutriscoreGrade: 'e',
    nutriscorePoints: 24,
    nutriscoreCategory: 'general',
    nutriBreakdown: NutriBreakdown(
      energy: 545, energyPts: 6,
      sugars: 38, sugarsPts: 9,
      saturatedFat: 14, saturatedFatPts: 10,
      sodium: 80, sodiumPts: 0,
      proteins: 6.5, proteinsPts: -2,
      fiber: 2.1, fiberPts: 0,
    ),
    allIngredients: ['şeker', 'buğday unu', 'bitkisel yağ (palm, %9,5)', 'fındık', 'süttozu', 'soya lesitini'],
    ingredientAllergenMarks: [[6, 17], [44, 50], [52, 59], [61, 65]],
    allergens: ['gluten', 'kuruyemiş', 'süt', 'soya'],
    allergenTraces: ['susam'],
    servingQuantity: 36,
    productQuantity: 36,
    quantityInfo: '36 g',
    dataSource: 'Local Database',
  );

  final missing = Product(
    barcode: 'LOC033758d59457',
    productName: 'Market Ürünü Besin Değeri Eksik',
    nutriscoreUnavailableReason: 'missing',
    nutriBreakdown: NutriBreakdown(energy: 120, sugars: null, saturatedFat: null, sodium: 300),
    allIngredients: ['su', 'tuz'],
  );

  // Ana ekrandaki "Son baktıkların" ve geçmişteki arama kutusu da çizilsin
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseService.addToHistory(missing);
    await DatabaseService.addToHistory(full);
  });
  tearDownAll(() => DatabaseService.deleteHistoryItems([full.barcode, missing.barcode]));

  tearDownAll(() => DatabaseService.setSetting('lang', 'tr'));

  Future<void> pumpAt(WidgetTester tester, Widget home, double scale, String lang) async {
    tester.view.physicalSize = const Size(1080, 1920); // 360 × 640 dp
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => DatabaseService.setSetting('lang', lang));
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: home));
    // Veritabanı okumaları gerçek zamanlı çalışır; art arda okunan her değer
    // için bir tur bekleyip ekranı yeniden çiz
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final lang in ['tr', 'en']) {
    final tr = lang == 'tr';
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('ana ekran, $lang, yazı ×$scale', (tester) async {
        await pumpAt(tester, const HomeScreen(), scale, lang);
        expect(tester.takeException(), isNull);
        expect(find.text(tr ? 'Son baktıkların' : 'Recently viewed'), findsOneWidget);
        expect(find.text(full.productName), findsOneWidget);
      });

      testWidgets('ürün sayfası (tam veri), $lang, yazı ×$scale', (tester) async {
        await pumpAt(tester, ProductDetailScreen(product: full), scale, lang);
        expect(find.text(tr ? 'Şeker yüksek' : 'High sugar'), findsOneWidget);
        expect(find.text(tr ? 'Tuz düşük' : 'Low salt'), findsOneWidget);
        // Sayfanın aşağısı da çizilsin
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });

      testWidgets('ürün sayfası (eksik veri), $lang, yazı ×$scale', (tester) async {
        await pumpAt(tester, ProductDetailScreen(product: missing), scale, lang);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text(tr ? 'kayıtlı değil' : 'not recorded'), findsWidgets);
      });

      testWidgets('geçmiş, $lang, yazı ×$scale', (tester) async {
        await pumpAt(tester, const HistoryScreen(), scale, lang);
        expect(tester.takeException(), isNull);
        expect(find.text(full.productName), findsOneWidget);
        expect(find.text(missing.productName), findsOneWidget);
        // Türkçe karakter ve büyük harf farkı aramayı etkilemez
        await tester.enterText(find.byType(TextField), 'CIKOLATALI');
        await tester.pump();
        expect(find.text(full.productName), findsOneWidget);
        expect(find.text(missing.productName), findsNothing);
        await tester.enterText(find.byType(TextField), 'yok böyle bir ürün');
        await tester.pump();
        expect(find.text(tr ? 'Aramana uyan kayıt yok' : 'No entries match your search'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
