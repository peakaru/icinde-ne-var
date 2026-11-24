import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icinde_ne_var/models/format.dart';
import 'package:icinde_ne_var/models/product.dart';
import 'package:icinde_ne_var/models/traffic_light.dart';
import 'package:icinde_ne_var/services/api_service.dart';
import 'package:icinde_ne_var/services/database_service.dart';
import 'package:icinde_ne_var/services/update_service.dart';

Product _product({
  double? sugars,
  double? satFat,
  double? sodium,
  String? category = 'general',
  String? reason,
}) =>
    Product(
      barcode: '8690504135913',
      productName: 'Test',
      nutriBreakdown: NutriBreakdown(sugars: sugars, saturatedFat: satFat, sodium: sodium),
      nutriscoreCategory: category,
      nutriscoreUnavailableReason: reason,
    );

void main() {
  group('Biçim', () {
    test('Türkçede ondalık ayırıcı virgül', () {
      expect(fmtNum(9.5, 1, 'tr'), '9,5');
      expect(fmtNum(9.5, 1, 'en'), '9.5');
      expect(fmtNum(1234.0, 0, 'tr'), '1234');
    });

    test('liste cümle içinde birleşir', () {
      expect(joinWords([], 'tr'), '');
      expect(joinWords(['şeker'], 'tr'), 'şeker');
      expect(joinWords(['şeker', 'tuz', 'protein'], 'tr'), 'şeker, tuz ve protein');
      expect(joinWords(['sugars', 'salt'], 'en'), 'sugars and salt');
    });

    test('arama Türkçe karakter ve büyük harf farkını yok sayar', () {
      expect(foldForSearch('ÇİKOLATALI GOFRET'), 'cikolatali gofret');
      expect(foldForSearch('çikolatalı'), foldForSearch('CIKOLATALI'));
      expect(foldForSearch('Şeker Ilık Ürün'), 'seker ilik urun');
    });
  });

  group('Trafik ışığı (FSA eşikleri)', () {
    test('yiyecek: Ülker gofret — şeker ve doymuş yağ yüksek, tuz düşük', () {
      final t = trafficLights(_product(sugars: 38, satFat: 14, sodium: 80));
      expect(t.map((e) => e.nutrient), ['sugars', 'saturated_fat', 'salt']);
      expect(t.map((e) => e.level),
          [NutrientLevel.high, NutrientLevel.high, NutrientLevel.low]);
      expect(t[2].per100, closeTo(0.2, 1e-9)); // 80 mg sodyum = 0,2 g tuz
    });

    test('eşik değerleri: tam sınır "düşük", üstü "yüksek"', () {
      expect(trafficLights(_product(sugars: 5)).single.level, NutrientLevel.low);
      expect(trafficLights(_product(sugars: 22.5)).single.level, NutrientLevel.medium);
      expect(trafficLights(_product(sugars: 22.6)).single.level, NutrientLevel.high);
    });

    test('içecek eşikleri daha düşük', () {
      final t = trafficLights(_product(sugars: 10.6, sodium: 10, category: 'beverage'));
      expect(t.map((e) => e.level), [NutrientLevel.medium, NutrientLevel.low]);
      // Aynı şeker yiyecekte "orta", 12 g içecekte "yüksek"
      expect(trafficLights(_product(sugars: 12, category: 'beverage')).single.level,
          NutrientLevel.high);
    });

    test('ürün grubu bilinmiyor ya da veri tutarsızsa gösterilmez', () {
      expect(trafficLights(_product(sugars: 38, category: null)), isEmpty);
      expect(trafficLights(_product(sugars: 38, reason: 'implausible')), isEmpty);
      expect(
          trafficLights(Product(barcode: '1', productName: 'x', nutriscoreCategory: 'general')),
          isEmpty);
    });

    test('etiket metni iki dilde', () {
      final t = trafficLights(_product(sugars: 38, satFat: 1)).toList();
      expect(trafficLightLabel(t[0], 'tr'), 'Şeker yüksek');
      expect(trafficLightLabel(t[1], 'tr'), 'Doymuş yağ düşük');
      expect(trafficLightLabel(t[0], 'en'), 'High sugar');
    });
  });

  group('Alerjen işaretleri', () {
    test('bozuk aralıklar atlanır', () {
      final p = Product.fromJson({
        'barcode': '1',
        'product_name': 'x',
        'ingredient_allergen_marks': [
          [0, 6],
          [10, 'x'],
          [3],
          'bozuk',
          [12, 20],
        ],
      });
      expect(p.ingredientAllergenMarks, [
        [0, 6],
        [12, 20],
      ]);
    });

    test('geçmişe kaydedilip geri okunur', () {
      final p = Product(
        barcode: '1',
        productName: 'x',
        allIngredients: ['buğday unu', 'süttozu'],
        ingredientAllergenMarks: [
          [0, 6],
          [12, 19],
        ],
      );
      final back = Product.fromJson(
          jsonDecode(DatabaseService.productToJson(p)) as Map<String, dynamic>);
      expect(back.ingredientAllergenMarks, p.ingredientAllergenMarks);
    });
  });

  test('arama sonucu "not açınca hesaplanır" bilgisini okur', () {
    expect(SearchResult.fromJson({'barcode': '1', 'grade_on_open': true}).gradeOnOpen, isTrue);
    expect(SearchResult.fromJson({'barcode': '1'}).gradeOnOpen, isFalse);
  });

  group('Sürüm kontrolü', () {
    const page = 'https://github.com/peakaru/icinde-ne-var/releases/tag/v1.3.0';

    test('GitHub yanıtından sürüm okunur', () {
      final info = UpdateService.parseRelease({'tag_name': 'v1.3.0', 'html_url': page});
      expect(info?.version, '1.3.0');
      expect(info?.url, page);
    });

    test('taslak, ön sürüm, başka adres ve bozuk etiket yok sayılır', () {
      expect(UpdateService.parseRelease({'tag_name': 'v1.3.0', 'html_url': page, 'draft': true}),
          isNull);
      expect(
          UpdateService.parseRelease(
              {'tag_name': 'v1.3.0', 'html_url': page, 'prerelease': true}),
          isNull);
      expect(
          UpdateService.parseRelease(
              {'tag_name': 'v1.3.0', 'html_url': 'https://example.com/releases/v1.3.0'}),
          isNull);
      expect(UpdateService.parseRelease({'tag_name': 'son-surum', 'html_url': page}), isNull);
      expect(UpdateService.parseRelease('bozuk'), isNull);
    });

    test('sürümler sayı olarak karşılaştırılır', () {
      expect(UpdateService.compareVersions('1.10.0', '1.9.2'), greaterThan(0));
      expect(UpdateService.compareVersions('1.3', '1.3.0'), 0);
      expect(UpdateService.compareVersions('1.2.0+3', '1.3.0'), lessThan(0));
    });
  });
}
