import 'dart:convert';
import 'legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _lang = 'tr';
  String _version = '';
  // Kullanıcının seçili alerjenleri (backend alerjen key'leriyle eşleşir)
  static const Map<String, String> _allergenLabelsTr = {
    'süt': '🥛 Süt / Laktoz',
    'gluten': '🌾 Gluten',
    'yumurta': '🥚 Yumurta',
    'soya': '🫘 Soya',
    'kuruyemiş': '🥜 Kuruyemiş',
    'balık': '🐟 Balık',
    'susam': '🍯 Susam',
    'hardal': '🌭 Hardal',
    'kereviz': '🥬 Kereviz',
    'sülfit': '🍷 Sülfit',
  };
  static const Map<String, String> _allergenLabelsEn = {
    'süt': '🥛 Milk / Lactose',
    'gluten': '🌾 Gluten',
    'yumurta': '🥚 Egg',
    'soya': '🫘 Soy',
    'kuruyemiş': '🥜 Nuts',
    'balık': '🐟 Fish',
    'susam': '🍯 Sesame',
    'hardal': '🌭 Mustard',
    'kereviz': '🥬 Celery',
    'sülfit': '🍷 Sulphites',
  };
  Map<String, String> get _allergenLabels =>
      _lang == 'tr' ? _allergenLabelsTr : _allergenLabelsEn;
  Set<String> _selectedAllergens = {};

  @override
  void initState() {
    super.initState();
    // Versiyon pubspec'ten otomatik okunur (elle güncellenmez)
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
    DatabaseService.getSetting('lang').then((v) {
      if (mounted) setState(() => _lang = v ?? 'tr');
    });
    _loadAllergens();
  }

  Future<void> _loadAllergens() async {
    final json = await DatabaseService.getSetting('user_allergens');
    if (json != null) {
      try {
        final list = List<String>.from(jsonDecode(json));
        if (mounted) setState(() => _selectedAllergens = list.toSet());
      } catch (_) {}
    }
  }

  Future<void> _toggleAllergen(String key) async {
    setState(() {
      if (_selectedAllergens.contains(key)) {
        _selectedAllergens.remove(key);
      } else {
        _selectedAllergens.add(key);
      }
    });
    await DatabaseService.setSetting('user_allergens', jsonEncode(_selectedAllergens.toList()));
  }

  Future<void> _setLang(String lang) async {
    await DatabaseService.setSetting('lang', lang);
    if (mounted) setState(() => _lang = lang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F1A),
        foregroundColor: Colors.white,
        title: Text(
          _lang == 'tr' ? '⚙️ Ayarlar' : '⚙️ Settings',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
        children: [
          // ─── Dil Seçimi ────────────────────────────────────
          _SettingCard(
            title: _lang == 'tr' ? 'Dil / Language' : 'Language / Dil',
            child: Row(
              children: [
                _LangButton(
                  label: '🇹🇷 Türkçe',
                  selected: _lang == 'tr',
                  onTap: () => _setLang('tr'),
                ),
                const SizedBox(width: 12),
                _LangButton(
                  label: '🇺🇸 English',
                  selected: _lang == 'en',
                  onTap: () => _setLang('en'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Alerjenlerim ─────────────────────────────────
          _SettingCard(
            title: _lang == 'tr' ? 'Alerjenlerim' : 'My Allergens',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lang == 'tr'
                      ? 'Seçtiklerin içeren ürünlerde kırmızı uyarı görürsün.'
                      : 'Products containing your selections show a red warning.',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allergenLabels.entries.map((entry) {
                    final key = entry.key;
                    final label = entry.value;
                    final selected = _selectedAllergens.contains(key);
                    return GestureDetector(
                      onTap: () => _toggleAllergen(key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFF43F5E).withOpacity(0.18) : Colors.white.withOpacity(0.05),
                          border: Border.all(
                            color: selected ? const Color(0xFFF43F5E) : Colors.white12,
                            width: selected ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selected) ...[
                              const Icon(Icons.warning_rounded, color: Color(0xFFF43F5E), size: 14),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              label,
                              style: TextStyle(
                                color: selected ? const Color(0xFFF43F5E) : Colors.white54,
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Gizlilik & Şartlar ────────────────────────────
          _SettingCard(
            title: _lang == 'tr' ? 'Yasal' : 'Legal',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LegalScreen(isTr: _lang == 'tr')),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _lang == 'tr' ? 'Gizlilik Politikası & Kullanım Şartları' : 'Privacy Policy & Terms of Use',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white38, semanticLabel: 'Open'),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Uygulama Hakkında ─────────────────────────────
          _SettingCard(
            title: _lang == 'tr' ? 'Hakkında' : 'About',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(_lang == 'tr' ? 'Uygulama' : 'App', 'İçinde Ne Var?'),
                _InfoRow(_lang == 'tr' ? 'Versiyon' : 'Version', _version),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Sorumluluk Reddi ──────────────────────────────
          _SettingCard(
            title: _lang == 'tr' ? 'Sorumluluk Reddi' : 'Disclaimer',
            child: Text(
              _lang == 'tr'
                  ? 'Bu uygulama yalnızca bilgilendirme amaçlıdır. Sağlık kararlarınız için mutlaka bir uzmana danışın. Bu uygulamayı kullanarak şartları okuduğunuzu ve kabul ettiğinizi onaylıyorsunuz.'
                  : 'This app is for informational purposes only. Always consult a professional for health decisions. By using this app you confirm that you have read and accepted the terms.',
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SettingCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF132720),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF10B981).withOpacity(0.2) : Colors.transparent,
            border: Border.all(
              color: selected ? const Color(0xFF10B981) : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? const Color(0xFF10B981) : Colors.white38,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
