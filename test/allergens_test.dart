import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icinde_ne_var/models/allergens.dart';

void main() {
  test('TR ve EN etiketleri aynı anahtarları kapsar', () {
    expect(Allergens.labels('tr').keys.toSet(),
        Allergens.labels('en').keys.toSet());
  });

  test('anahtarlar backend ALLERGENS ile birebir aynı', () {
    final src = File('backend/analysis.py').readAsStringSync();
    final block = RegExp(r'ALLERGENS = \{(.*?)\n\}', dotAll: true)
        .firstMatch(src)!
        .group(1)!;
    final backendKeys = RegExp(r'^    "([^"]+)":', multiLine: true)
        .allMatches(block)
        .map((m) => m.group(1))
        .toSet();
    expect(backendKeys, isNotEmpty);
    expect(Allergens.labels('tr').keys.toSet(), backendKeys);
  });

  test('etiket çevirisi ve bilinmeyen anahtar', () {
    expect(Allergens.label('süt', 'en'), contains('Milk'));
    expect(Allergens.label(' SÜT ', 'tr'), contains('Süt'));
    expect(Allergens.label('bilinmeyen', 'en'), 'bilinmeyen');
  });
}
