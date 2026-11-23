import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/database_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Dil ayarı yoksa telefon dilinden belirle: Türkçe → tr, diğerleri → en.
  // Kullanıcı hiç seçim yapmak zorunda kalmaz; istersen ayarlardan değiştirir.
  final savedLang = await DatabaseService.getSetting('lang');
  if (savedLang == null) {
    final deviceLang = PlatformDispatcher.instance.locale.languageCode;
    await DatabaseService.setSetting('lang', deviceLang == 'tr' ? 'tr' : 'en');
  }

  // Onboarding sadece ilk açılışta gösterilir
  final onboarded = await DatabaseService.getSetting('onboarding_done');

  runApp(IcindeNeVarApp(showOnboarding: onboarded == null));
}

class IcindeNeVarApp extends StatelessWidget {
  final bool showOnboarding;
  const IcindeNeVarApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'İçinde Ne Var?',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D1F1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1F1A),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
