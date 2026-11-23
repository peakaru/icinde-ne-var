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
  });
}
