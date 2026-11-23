import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:icinde_ne_var/models/product.dart';

void main() {
  group('Product.fromJson', () {
    test('tam veri parse edilir', () {
      final json = {
        'barcode': '8690120050393',
        'product_name': 'Torku Kakaolu Tahin Helvası 200 G',
        'brand': 'Torku',
        'image_url': 'https://ornek.com/img.jpg',
        'nutri_score': {
          'grade': 'D',
          'points': 13,
          'breakdown': {
            'energy': {'value': 526.1, 'unit': 'kcal', 'points': 5},
            'sugars': {'value': 47.4, 'unit': 'g', 'points': 10},
            'saturated_fat': {'value': 4.2, 'unit': 'g', 'points': 3},
            'sodium': {'value': 160.0, 'unit': 'mg', 'points': 1},
            'proteins': {'value': 12.5, 'unit': 'g', 'points': -4},
            'fiber': {'value': null, 'unit': 'g', 'points': null},
          },
        },
        'found_risks': [
          {
            'name': 'Şeker (İlave)',
            'ewg_score': 6,
            'risk': 'Obezite riski',
            'evidence': 'moderate',
            'color': 'orange',
            'source': 'EFSA/FDA izinli',
          },
        ],
        'allergens': ['susam', 'gluten'],
        'all_ingredients': ['Tahin', 'Şeker', 'kakao'],
        'critical_safety_rule': false,
        'product_quantity': 200.0,
        'serving_quantity': 0.0,
        'serving_size_text': '',
        'quantity_info': '200 g',
        'quantity_source': 'regex',
        'quantity_unit': 'g',
      };

      final p = Product.fromJson(json);

      expect(p.barcode, '8690120050393');
      expect(p.productName, contains('Torku'));
      expect(p.brand, 'Torku');
      expect(p.imageUrl, 'https://ornek.com/img.jpg');
      expect(p.nutriscoreGrade, 'D');
      expect(p.nutriscorePoints, 13);
      expect(p.nutriBreakdown!.energy, 526.1);
      expect(p.nutriBreakdown!.energyPts, 5);
      expect(p.nutriBreakdown!.fiber, isNull); // null değer null kalmalı
      expect(p.foundRisks!.length, 1);
      expect(p.foundRisks!.first.evidence, 'moderate');
      expect(p.foundRisks!.first.color, 'orange');
      expect(p.foundRisks!.first.source, 'EFSA/FDA izinli');
      expect(p.allergens, contains('susam'));
      expect(p.allIngredients!.length, 3);
      expect(p.productQuantity, 200.0);
      expect(p.quantityInfo, '200 g');
      expect(p.quantityUnit, 'g');
      expect(p.hasPackage, isTrue);   // 200 > 0
      expect(p.hasServing, isFalse);  // 0
    });

    test('minimal veri (data_warning) parse edilir', () {
      final json = {
        'barcode': '123',
        'product_name': 'Bilinmeyen',
        'data_warning': true,
      };
      final p = Product.fromJson(json);
      expect(p.dataWarning, isTrue);
      expect(p.nutriscoreGrade, isNull);
      expect(p.foundRisks, isNull);
      expect(p.quantityUnit, 'g'); // default
    });

    test('eski kayıt (quantity alanları yok) crash etmez', () {
      final json = {
        'barcode': '123',
        'product_name': 'Eski',
      };
      final p = Product.fromJson(json);
      expect(p.productQuantity, 0);
      expect(p.quantityInfo, '');
      expect(p.quantitySource, 'unknown');
    });

    test('code fallback çalışır (barcode yoksa code kullanılır)', () {
      final json = {'code': '999', 'product_name': 'X'};
      final p = Product.fromJson(json);
      expect(p.barcode, '999');
    });

    test('nutriscoreColor grade eşleşir', () {
      final mk = (String? g) => Product.fromJson({
            'barcode': '1', 'product_name': 'x',
            'nutri_score': {'grade': g},
          }).nutriscoreColor;
      expect(mk('A'), const Color(0xFF038141));
      expect(mk('E'), const Color(0xFFE63E11));
      expect(mk(null), const Color(0xFF64748B)); // bilinmeyen gri
    });
  });

  group('RiskIngredient.fromJson', () {
    test('kanıt alanları parse edilir', () {
      final r = RiskIngredient.fromJson({
        'name': 'Sodyum Nitrit',
        'ewg_score': 9,
        'risk': 'Nitrozamin riski',
        'evidence': 'strong',
        'color': 'red',
        'source': 'IARC Grup 1',
      });
      expect(r.ewgScore, 9);
      expect(r.evidence, 'strong');
      expect(r.source, 'IARC Grup 1');
    });

    test('eski format (kanıt yok) null kalır', () {
      final r = RiskIngredient.fromJson({
        'name': 'Sitrik Asit',
        'ewg_score': 2,
        'risk': 'Güvenli',
      });
      expect(r.evidence, isNull);
      expect(r.color, isNull);
      expect(r.source, isNull);
    });
  });

  group('NutriBreakdown.fromJson', () {
    test('null değerler güvenli işlenir', () {
      final b = NutriBreakdown.fromJson({
        'energy': {'value': null, 'points': null},
        'sugars': null, // alan hiç yok
      });
      expect(b.energy, isNull);
      expect(b.energyPts, isNull);
      expect(b.sugars, isNull);
    });
  });
}
