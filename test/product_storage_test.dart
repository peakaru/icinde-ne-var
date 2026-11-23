import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icinde_ne_var/models/product.dart';
import 'package:icinde_ne_var/services/database_service.dart';

/// Geçmiş, favoriler ve çevrimdışı cache ürünü productToJson ile saklayıp
/// Product.fromJson ile geri okur; gidiş-dönüşte hiçbir alan kaybolmamalı.
void main() {
  final original = Product(
    barcode: '8690504040248',
    productName: 'Fındıklı Gofret',
    brand: 'Ülker',
    nutriscoreGrade: 'd',
    nutriscorePoints: 15,
    nutriBreakdown: NutriBreakdown(energy: 530, energyPts: 6, sugars: 40, sugarsPts: 8),
    allIngredients: ['şeker', 'buğday unu', 'fındık'],
    allergens: ['gluten', 'kuruyemiş'],
    allergenTraces: ['kuruyemiş'],
    foundRisks: [
      RiskIngredient(
        name: 'Palm yağı',
        nameEn: 'Palm oil',
        ewgScore: 4,
        risk: 'Doymuş yağ oranı yüksek',
        riskEn: 'High in saturated fat',
        evidence: 'moderate',
        color: 'orange',
        source: 'EFSA 2016',
        sourceEn: 'EFSA 2016 (EN)',
      ),
    ],
    servingQuantity: 35,
    productQuantity: 140,
    quantityInfo: '140 g',
    dataSource: 'Local Database',
  );

  Product roundTrip(Product p) =>
      Product.fromJson(jsonDecode(DatabaseService.productToJson(p)) as Map<String, dynamic>);

  test('İngilizce risk metinleri saklanıp geri okunur', () {
    final r = roundTrip(original).foundRisks!.single;
    expect(r.nameEn, 'Palm oil');
    expect(r.riskEn, 'High in saturated fat');
    expect(r.sourceEn, 'EFSA 2016 (EN)');
    expect(r.evidence, 'moderate');
  });

  test('besin, porsiyon ve kaynak alanları korunur', () {
    final p = roundTrip(original);
    expect(p.nutriscoreGrade, 'd');
    expect(p.nutriBreakdown!.sugarsPts, 8);
    expect(p.servingQuantity, 35);
    expect(p.quantityInfo, '140 g');
    expect(p.dataSource, 'Local Database');
    expect(p.allergens, ['gluten', 'kuruyemiş']);
    expect(p.allergenTraces, ['kuruyemiş']);
    expect(p.allergensContained, ['gluten']);
  });

  test('eski kayıtta allergen_traces yoksa hepsi "içerir" sayılır', () {
    final p = Product.fromJson({'barcode': '1', 'product_name': 'x', 'allergens': ['süt']});
    expect(p.allergenTraces, isEmpty);
    expect(p.allergensContained, ['süt']);
  });

  test('Nutri-Score 2023 alanları ve notsuz ürünün besin değerleri korunur', () {
    final graded = roundTrip(Product.fromJson({
      'barcode': '1',
      'product_name': 'Portakal Suyu',
      'nutri_score': {
        'grade': 'C', 'points': 4, 'source': 'computed', 'category': 'beverage',
        'breakdown': {
          'energy': {'value': 45, 'points': 3},
          'sweeteners': {'value': false, 'points': 0},
          'fruits_vegetables_legumes': {'value': 100, 'points': -6},
        },
      },
    }));
    expect(graded.nutriscoreCategory, 'beverage');
    expect(graded.nutriscoreSource, 'computed');
    expect(graded.nutriBreakdown!.fruitsVegLegumes, 100);
    expect(graded.nutriBreakdown!.fruitsVegLegumesPts, -6);
    expect(graded.nutriBreakdown!.sweetenersPts, 0);

    final ungraded = roundTrip(Product.fromJson({
      'barcode': '2',
      'product_name': 'Bisküvi',
      'nutri_score': {
        'grade': null, 'points': null, 'unavailable_reason': 'missing',
        'breakdown': {'energy': {'value': 480, 'points': null}},
      },
    }));
    expect(ungraded.nutriscoreGrade, isNull);
    expect(ungraded.nutriscoreUnavailableReason, 'missing');
    expect(ungraded.nutriBreakdown!.energy, 480);
  });
}
