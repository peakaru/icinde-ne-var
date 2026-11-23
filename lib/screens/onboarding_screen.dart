import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/allergens.dart';
import '../services/database_service.dart';
import 'home_screen.dart';
import 'legal_screen.dart';

/// İlk açılış kurulumu: (1) karşılama, (2) alerjen profili.
/// Sadece bir kez gösterilir (onboarding_done flag'i), dil telefondan gelir.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _kvkkAccepted = false;
  String _lang = 'tr';
  Set<String> _selectedAllergens = {};

  Map<String, String> get _allergenLabels => Allergens.labels(_lang);

  bool get _isTr => _lang == 'tr';

  @override
  void initState() {
    super.initState();
    DatabaseService.getSetting('lang').then((v) {
      if (mounted) setState(() => _lang = v ?? 'tr');
    });
  }

  Future<void> _finish() async {
    await DatabaseService.setSetting('onboarding_done', '1');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _step == 0 ? _buildWelcome() : _buildAllergens(),
        ),
      ),
    );
  }

  // ─── Adım 1: Karşılama ───
  Widget _buildWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        // Logo
        Container(
          width: 110, height: 110,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 2),
          ),
          child: const Text('🛒', style: TextStyle(fontSize: 48)),
        ),
        const SizedBox(height: 28),
        Text(
          _isTr ? 'İçinde Ne Var?' : 'What\'s Inside?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          _isTr
              ? 'Ürünleri tara, içindekileri ve sağlıklılığını anında gör.'
              : 'Scan products, instantly see what\'s inside and how healthy they are.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 36),
        _featureRow('📷', _isTr ? 'Barkodu tara' : 'Scan the barcode',
            _isTr ? 'Markette ürünü anında analiz et' : 'Analyze products instantly at the store'),
        const SizedBox(height: 14),
        _featureRow('⚖️', _isTr ? 'Karşılaştır' : 'Compare',
            _isTr ? 'İki üründen hangisi daha sağlıklı?' : 'Which of two products is healthier?'),
        const SizedBox(height: 14),
        _featureRow('⚠️', _isTr ? 'Alerjen uyarısı' : 'Allergen alerts',
            _isTr ? 'Senin alerjenlerini içeren ürünlerde uyar' : 'Get warned about your allergens'),
        const Spacer(flex: 3),
        // Başla
        GestureDetector(
          onTap: () => setState(() => _step = 1),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.35),
                  blurRadius: 20, offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              _isTr ? 'Başla 👋' : 'Get Started 👋',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 34),
      ],
    );
  }

  Widget _featureRow(String emoji, String title, String desc) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Adım 2: Alerjen profili ───
  Widget _buildAllergens() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        Text('🚨', textAlign: TextAlign.center, style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 16),
        Text(
          _isTr ? 'Alerjenin var mı?' : 'Any allergens?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          _isTr
              ? 'Seçtiklerini içeren ürünlerde kırmızı uyarı görürsün. Sonradan ayarlardan değiştirebilirsin.'
              : 'Products containing your selections show a red warning. You can change this later in settings.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: _allergenLabels.entries.map((entry) {
            final selected = _selectedAllergens.contains(entry.key);
            return GestureDetector(
              onTap: () => setState(() {
                selected
                    ? _selectedAllergens.remove(entry.key)
                    : _selectedAllergens.add(entry.key);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFF43F5E).withOpacity(0.18) : Colors.white.withOpacity(0.05),
                  border: Border.all(
                    color: selected ? const Color(0xFFF43F5E) : Colors.white12,
                    width: selected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const Spacer(flex: 3),
        // KVKK bilgilendirme onayı (varsayılan kabul + politika linki; veri toplanmaz)
        Row(
          children: [
            Checkbox(
              value: _kvkkAccepted,
              onChanged: (v) => setState(() => _kvkkAccepted = v ?? true),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LegalScreen(isTr: _isTr)),
                ),
                child: Text.rich(
                  TextSpan(
                    text: _isTr
                        ? "Gizlilik Politikası ve Kullanım Şartları'nı okudum, kabul ediyorum"
                        : "I have read and accept the Privacy Policy and Terms of Use",
                    style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Bitir
        GestureDetector(
          onTap: () async {
            if (!_kvkkAccepted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_isTr
                    ? 'Devam etmek için gizlilik politikası onayı gerekli.'
                    : 'Privacy policy acceptance is required to continue.'),
                backgroundColor: const Color(0xFFB45309),
              ));
              return;
            }
            await DatabaseService.setSetting(
                'user_allergens', jsonEncode(_selectedAllergens.toList()));
            _finish();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _isTr ? 'Hazırım!' : 'I\'m Ready!',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _kvkkAccepted
              ? _finish
              : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_isTr
                        ? 'Devam etmek için gizlilik politikası onayı gerekli.'
                        : 'Privacy policy acceptance is required to continue.'),
                    backgroundColor: const Color(0xFFB45309),
                  )),
          child: Text(
            _isTr ? 'Atla' : 'Skip',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
