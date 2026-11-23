import 'package:flutter_test/flutter_test.dart';
import 'package:icinde_ne_var/models/product.dart';
import 'package:icinde_ne_var/services/compare_store.dart';

Product p(String barcode, String? grade) =>
    Product(barcode: barcode, productName: barcode, nutriscoreGrade: grade);

void main() {
  test('daha iyi Nutri-Score kazanır', () {
    final a = p('1', 'b'), b = p('2', 'd');
    expect(CompareStore.healthier(a, b), same(a));
    expect(CompareStore.healthier(b, a), same(a));
  });

  test('notu bilinmeyen ürün kazanamaz', () {
    expect(CompareStore.healthier(p('1', null), p('2', 'a')), isNull);
    expect(CompareStore.healthier(p('1', 'e'), p('2', null)), isNull);
    expect(CompareStore.healthier(p('1', '?'), p('2', 'c')), isNull);
  });

  test('eşit notta kazanan yok', () {
    expect(CompareStore.healthier(p('1', 'C'), p('2', 'c')), isNull);
  });
}
