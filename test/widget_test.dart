import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:icinde_ne_var/main.dart';
import 'package:icinde_ne_var/screens/onboarding_screen.dart';

void main() {
  // sqflite test ortamında ffi factory gerekir (mobil değil masaüstü test)
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    // Onboarding kapalı — ana ekran açılır (gerçek kullanımda ilk açılışta görünür)
    await tester.pumpWidget(const IcindeNeVarApp(showOnboarding: false));
    await tester.pump(const Duration(milliseconds: 300)); // animasyonlar açılsın
    expect(find.byType(IcindeNeVarApp), findsOneWidget);
  });

  testWidgets('Onboarding: karşılama + alerjen adımı', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    // Adım 1: karşılama
    expect(find.text('İçinde Ne Var?'), findsOneWidget);
    // Başla → adım 2: alerjenler
    await tester.tap(find.textContaining('Başla'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Alerjenin var mı?'), findsOneWidget);
  });
}
