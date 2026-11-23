import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product.dart';
import '../services/compare_store.dart';
import '../services/database_service.dart';
import 'compare_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final String? imagePath; // Sadece galeriden gelince dolu
  const ProductDetailScreen({super.key, required this.product, this.imagePath});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isFav = false;
  String _lang = 'tr';
  // Porsiyon modu: 0 = 100g, 1 = porsiyon, 2 = tüm paket
  // initState'te ürüne göre belirlenir: porsiyon > paket > 100g
  int _portionMode = 0;
  final TextEditingController _gramCtrl = TextEditingController();
  double? _manualGrams;

  // besinler tamamen bos/0 ise gida disi urun olabilir -> NS/besin gizle
  bool get _hasNutri {
    final nb = widget.product.nutriBreakdown;
    return nb == null ||
        (nb.energy ?? 0) != 0 ||
        (nb.sugars ?? 0) != 0 ||
        (nb.saturatedFat ?? 0) != 0 ||
        (nb.sodium ?? 0) != 0 ||
        (nb.proteins ?? 0) != 0 ||
        (nb.fiber ?? 0) != 0;
  }
  // Açık olan risk detayı (null = hepsi kapalı)
  int? _expandedRisk;
  // Kullanıcının alerjen profili (ayarlarlaştır)
  List<String> _userAllergens = [];

  @override
  void initState() {
    super.initState();
    // Varsayılan mod: porsiyon varsa porsiyon, yoksa paket, o da yoksa 100g
    final p = widget.product;
    _portionMode = p.hasServing ? 1 : (p.hasPackage ? 2 : 0);
    _check();
  }

  Future<void> _check() async {
    final fav = await DatabaseService.isFavorite(widget.product.barcode);
    final lang = await DatabaseService.getSetting('lang') ?? 'tr';
    // Alerjen profili (JSON liste olarak kayıtlı)
    final allergenJson = await DatabaseService.getSetting('user_allergens');
    List<String> userAllergens = [];
    if (allergenJson != null) {
      try {
        userAllergens = List<String>.from(jsonDecode(allergenJson));
      } catch (_) {}
    }
    if (mounted) setState(() { _isFav = fav; _lang = lang; _userAllergens = userAllergens; });
  }

  Future<void> _toggleFav() async {
    if (_isFav) {
      await DatabaseService.removeFavorite(widget.product.barcode);
    } else {
      await DatabaseService.addFavorite(widget.product);
    }
    if (!mounted) return;
    setState(() => _isFav = !_isFav);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_isFav
          ? (_lang == 'tr' ? 'Favorilere eklendi' : 'Added to favorites')
          : (_lang == 'tr' ? 'Favorilerden çıkarıldı' : 'Removed from favorites')),
      duration: const Duration(seconds: 1),
    ));
  }

  /// Ürün analiz metnini paylaş (WhatsApp/Instagram vs.)
  Future<void> _shareProduct() async {
    final p = widget.product;
    final grade = (p.nutriscoreGrade ?? '?').toUpperCase();
    final buf = StringBuffer();
    buf.writeln('🛒 ${p.productName}');
    if ((p.brand ?? '').isNotEmpty) buf.writeln('🏷️ ${p.brand}');
    buf.writeln('Nutri-Score: $grade');
    if (p.foundRisks != null && p.foundRisks!.isNotEmpty) {
      buf.writeln('⚠️ ${p.foundRisks!.length} ${_lang == 'tr' ? 'dikkat gerektiren içerik' : 'risky ingredients'}');
    }
    if (p.nutriBreakdown?.energy != null) {
      buf.writeln('🔥 ${p.nutriBreakdown!.energy!.toStringAsFixed(0)} kcal/100${p.quantityUnit}');
    }
    buf.writeln();
    buf.writeln(_lang == 'tr'
        ? '📱 İçinde Ne Var? ile tarandı'
        : '📱 Scanned with İçinde Ne Var?');
    await Share.share(buf.toString());
  }

  /// Karşılaştırma sepetine ekle; 2. üründe karşılaştırma ekranını aç
  void _compareProduct() {
    final res = CompareStore.add(widget.product);
    if (res == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_lang == 'tr'
            ? 'Bu ürün zaten karşılaştırmada.'
            : 'Already in comparison.'),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    if (res == 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_lang == 'tr'
            ? 'Karşılaştırmaya eklendi (1/2) — başka bir ürün açıp ⚖️ simgesine bas'
            : 'Added to compare (1/2) — open another product and tap ⚖️'),
        duration: const Duration(seconds: 3),
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F1A),
        foregroundColor: Colors.white,
        title: Text(
          _lang == 'tr' ? 'Ürün Analizi' : 'Product Analysis',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows_rounded, color: Colors.white70, size: 26),
            onPressed: _compareProduct,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 24),
            onPressed: _shareProduct,
          ),
          IconButton(
            icon: Icon(
              _isFav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xFFFBBF24),
              size: 30,
            ),
            onPressed: _toggleFav,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ─── Ürün Başlığı ───────────────────────────────────
            _SectionCard(children: [
              // Fotoğraf: galeriden geldiyse dosya, yoksa backend'in görseli
              if (widget.imagePath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(widget.imagePath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
              ] else if (p.imageUrl != null && p.imageUrl!.isNotEmpty) ...[
                Semantics(
                  label: _lang == 'tr' ? 'Ürün fotoğrafı' : 'Product photo',
                  image: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      p.imageUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : const SizedBox(height: 180),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                _lang == 'tr' ? 'ÜRÜN' : 'PRODUCT',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(p.productName,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              if (p.brand != null) ...[
                const SizedBox(height: 4),
                Text(p.brand!, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Text(p.barcode, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                if (p.dataSource.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.storage_rounded, size: 11, color: Colors.white.withOpacity(0.4)),
                      const SizedBox(width: 4),
                      Text(
                        _sourceLabel(p.dataSource),
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                      ),
                    ]),
                  ),
                ],
              ]),
            ]),

            // ─── Alerjen Profili Uyarısı (kullanıcının seçtikleriyle eşleşme) ──
            ..._buildAllergenAlert(p),

            // ─── Kritik Uyarı ────────────────────────────────────
            if (p.criticalSafetyRule) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF43F5E).withOpacity(0.5)),
                ),
                child: Row(children: [
                  const Icon(Icons.dangerous_rounded, color: Color(0xFFF43F5E), size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    _lang == 'tr' ? '⚠️ Kritik sağlık riski içeriği tespit edildi!' : '⚠️ Critical health risk ingredient detected!',
                    style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold, fontSize: 14),
                  )),
                ]),
              ),
            ],

            // ─── Veri Eksik Uyarısı ──────────────────────────────
            if (p.dataWarning && p.nutriscoreGrade == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFFBBF24), size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    _lang == 'tr'
                        ? 'Bu ürün için detaylı besin verisi bulunamadı.'
                        : 'Detailed nutrition data not available for this product.',
                    style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 13, height: 1.4),
                  )),
                ]),
              ),
            ],

            const SizedBox(height: 16),

            // ─── Nutri-Score ─────────────────────────────────────
            if (_hasNutri) ...[
            _SectionCard(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('NUTRI-SCORE',
                      style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.5)),
                  GestureDetector(
                    onTap: () => _showNutriInfo(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.help_outline_rounded, size: 13, color: Colors.white38),
                          const SizedBox(width: 5),
                          Text(_lang == 'tr' ? 'Nasıl hesaplandı?' : 'How is it calculated?',
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(children: [
                // Grade badge
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: p.nutriscoreColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      (p.nutriscoreGrade ?? '?').toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nutriscoreLabel(p.nutriscoreGrade),
                      style: TextStyle(color: p.nutriscoreColor, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (p.nutriscorePoints != null)
                      Text('${_lang == 'tr' ? 'Puan' : 'Points'}: ${p.nutriscorePoints}',
                          style: const TextStyle(color: Colors.white54, fontSize: 14)),
                    const SizedBox(height: 12),
                    _NutriScaleBar(grade: p.nutriscoreGrade),
                  ],
                )),
              ]),
            ]),
            ] else ...[
              const SizedBox(height: 10),
              _SectionCard(children: [
                Text(
                  _lang == 'tr'
                      ? 'Bu ürüne ait besin verisi bulunmuyor. Gıda ürünü olmayabilir (kozmetik, temizlik vb.).'
                      : 'No nutrition data for this product. It may not be a food item (cosmetics, cleaning, etc.).',
                  style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                ),
              ]),
            ],

            const SizedBox(height: 16),

            // ─── Besin Değerleri (Breakdown) ──────────────────────
            if (_hasNutri && p.nutriBreakdown != null) ...[
              _SectionCard(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _lang == 'tr' ? 'BESİN DEĞERLERİ' : 'NUTRITION',
                      style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.5),
                    ),
                    // Porsiyon/paket bilgisi (varsa)
                    if (p.quantityInfo.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                        ),
                        child: Text(
                          p.quantityInfo,
                          style: const TextStyle(
                            color: Color(0xFF2EE89A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),

                // ─── 3'lü toggle (100g / porsiyon / paket) ───
                if (p.hasServing || p.hasPackage) ...[
                  const SizedBox(height: 12),
                  _PortionToggle(
                    mode: _portionMode,
                    hasServing: p.hasServing,
                    hasPackage: p.hasPackage,
                    onChanged: (m) => setState(() => _portionMode = m),
                    lang: _lang,
                    unit: p.quantityUnit, // "g" veya "ml"
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    _lang == 'tr' ? '(100 g başına değerler)' : '(per 100 g)',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                ],

                // ─── Manuel gramaj (paket bilgisi olmayanlar dahil) ───
                Row(
                  children: [
                    Icon(Icons.scale, color: Colors.white38, size: 18,
                        semanticLabel: _lang == 'tr' ? 'Manuel gramaj' : 'Manual amount'),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _gramCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: _lang == 'tr' ? 'Manuel miktar (g/ml)' : 'Manual amount (g/ml)',
                          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF10B981))),
                          suffixText: _manualGrams != null
                              ? '×' + (_manualGrams! / 100).toStringAsFixed(2)
                              : null,
                          suffixStyle: const TextStyle(color: Color(0xFF10B981), fontSize: 11),
                        ),
                        onChanged: (v) => setState(() {
                          _manualGrams = double.tryParse(v.replaceAll(',', '.'));
                        }),
                      ),
                    ),
                    if (_manualGrams != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: _lang == 'tr' ? 'Temizle' : 'Clear',
                        color: Colors.white38,
                        onPressed: () {
                          _gramCtrl.clear();
                          setState(() => _manualGrams = null);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Çarpan: manuel > porsiyon (×serving/100) > paket (×quantity/100)
                Builder(builder: (context) {
                  double mult = 1.0;
                  if (_manualGrams != null && _manualGrams! > 0) mult = _manualGrams! / 100;
                  else if (_portionMode == 1 && p.hasServing) mult = p.servingQuantity / 100;
                  else if (_portionMode == 2 && p.hasPackage) mult = p.productQuantity / 100;
                  // tuz eşdeğeri: sodyum(mg) × 2.5 → g (etiketlerdeki "Tuz" ile aynı dil)
                  final double? tuzG = p.nutriBreakdown?.sodium == null
                      ? null
                      : p.nutriBreakdown!.sodium! * mult * 2.5 / 1000;
                  return Column(
                    children: [
                      _NutrimentRow(_lang == 'tr' ? 'Enerji' : 'Energy', p.nutriBreakdown!.energy, 'kcal', mult),
                      _NutrimentRow(_lang == 'tr' ? 'Şeker' : 'Sugars', p.nutriBreakdown!.sugars, 'g', mult),
                      _NutrimentRow(_lang == 'tr' ? 'Doymuş Yağ' : 'Sat. Fat', p.nutriBreakdown!.saturatedFat, 'g', mult),
                      _NutrimentRow(_lang == 'tr' ? 'Sodyum' : 'Sodium', p.nutriBreakdown!.sodium, 'mg', mult,
                          tuzG == null
                              ? null
                              : (_lang == 'tr' ? 'tuz' : 'salt') +
                                  ' ' +
                                  (tuzG < 1 ? tuzG.toStringAsFixed(2) : tuzG.toStringAsFixed(1)) +
                                  ' g'),
                      _NutrimentRow(_lang == 'tr' ? 'Protein' : 'Protein', p.nutriBreakdown!.proteins, 'g', mult),
                      _NutrimentRow(_lang == 'tr' ? 'Lif' : 'Fiber', p.nutriBreakdown!.fiber, 'g', mult),
                    ],
                  );
                }),
              ]),
              const SizedBox(height: 16),
            ],

            // ─── Feragat (desteklenmeyen iddialara karşı bilgilendirme) ──
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                _lang == 'tr'
                    ? 'Puanlar ve içerik analizleri bilgilendirme amaçlıdır; tıbbi veya beslenme tavsiyesi değildir. Alerjiniz varsa ambalaj etiketini esas alın.'
                    : 'Grades and ingredient analyses are for information only and are not medical or dietary advice. For allergies, rely on the package label.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 10.5, height: 1.4, fontStyle: FontStyle.italic),
              ),
            ),

            // ─── Risk İçerikleri ──────────────────────────────────
            if (p.foundRisks != null && p.foundRisks!.isNotEmpty) ...[
              _SectionCard(children: [
                Text(
                  _lang == 'tr' ? '⚠️ DİKKAT GEREKTİREN İÇERİKLER' : '⚠️ RISK INGREDIENTS',
                  style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                // Sıralama: kanıt düzeyi güçlü olanlar üstte (strong > moderate > limited)
                ..._sortedRisks(p.foundRisks!).asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final expanded = _expandedRisk == idx;
                  final evColor = _evidenceColor(r.evidence);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [
                      // Satır: skor + isim + kanıt badge (tıklanınca açılır)
                      InkWell(
                        onTap: () => setState(() => _expandedRisk = expanded ? null : idx),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Row(children: [
                            // EWG skoru renk göstergesi
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: _ewgColor(r.ewgScore).withOpacity(0.2),
                                border: Border.all(color: _ewgColor(r.ewgScore).withOpacity(0.6)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(child: Text('${r.ewgScore}',
                                  style: TextStyle(color: _ewgColor(r.ewgScore), fontWeight: FontWeight.bold, fontSize: 13))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                                (_lang == 'en' && (r.nameEn ?? '').isNotEmpty) ? r.nameEn! : r.name,
                                style: const TextStyle(color: Colors.white70, fontSize: 14))),
                            // Kanıt düzeyi badge (backend'den geliyorsa)
                            if (r.evidence != null && r.evidence!.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: evColor.withOpacity(0.15),
                                  border: Border.all(color: evColor.withOpacity(0.5)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _evidenceLabel(r.evidence, _lang),
                                  style: TextStyle(color: evColor, fontSize: 10, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                              color: Colors.white24, size: 20,
                            ),
                          ]),
                        ),
                      ),
                      // Genişletilmiş detay: risk + kaynak
                      if (expanded) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 4, left: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (r.risk.isNotEmpty) ...[
                              Text(
                                (_lang == 'en' && (r.riskEn ?? '').isNotEmpty) ? r.riskEn! : r.risk,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                              const SizedBox(height: 8),
                            ],
                            if (r.source != null && r.source!.isNotEmpty) ...[
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.menu_book_rounded, color: Colors.white30, size: 14),
                                const SizedBox(width: 6),
                                Expanded(child: Text(
                                  (_lang == 'en' && (r.sourceEn ?? '').isNotEmpty) ? r.sourceEn! : r.source!,
                                  style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                                )),
                              ]),
                            ],
                          ]),
                        ),
                      ],
                    ]),
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  _lang == 'tr'
                      ? '* EWG Puanı: 1 (düşük risk) → 10 (yüksek risk) • Kanıt: gücüne göre rozet'
                      : '* EWG Score: 1 (low) → 10 (high) • Badge = evidence level',
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // ─── Alerjenler ───────────────────────────────────────
            if (p.allergens != null && p.allergens!.isNotEmpty) ...[
              _SectionCard(children: [
                Text(
                  _lang == 'tr' ? 'ALERJENLER' : 'ALLERGENS',
                  style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: p.allergens!.map((a) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withOpacity(0.15),
                      border: Border.all(color: const Color(0xFFF43F5E).withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(a, style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 13)),
                  )).toList(),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // ─── İçindekiler ──────────────────────────────────────
            if (p.allIngredients != null && p.allIngredients!.isNotEmpty) ...[
              _SectionCard(children: [
                Text(
                  _lang == 'tr' ? 'İÇİNDEKİLER' : 'INGREDIENTS',
                  style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  p.allIngredients!.join(', '),
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _nutriscoreLabel(String? grade) {
    switch (grade?.toUpperCase()) {
      case 'A': return _lang == 'tr' ? 'Çok İyi' : 'Very Good';
      case 'B': return _lang == 'tr' ? 'İyi' : 'Good';
      case 'C': return _lang == 'tr' ? 'Orta' : 'Average';
      case 'D': return _lang == 'tr' ? 'Kötü' : 'Poor';
      case 'E': return _lang == 'tr' ? 'Çok Kötü' : 'Very Poor';
      default:  return _lang == 'tr' ? 'Bilinmiyor' : 'Unknown';
    }
  }

  Color _ewgColor(int score) {
    if (score <= 2) return const Color(0xFF10B981);
    if (score <= 4) return const Color(0xFFFBBF24);
    if (score <= 6) return const Color(0xFFEE8100);
    return const Color(0xFFE63E11);
  }

  /// Veri kaynağı etiketi (şeffaflık)
  String _sourceLabel(String source) {
    switch (source) {
      case 'Local Database': return _lang == 'tr' ? 'Yerel Veritabanı' : 'Local DB';
      case 'Open Food Facts': return 'Open Food Facts';
      case 'Local + OFF': return _lang == 'tr' ? 'Yerel + OFF' : 'Local + OFF';
      default: return source;
    }
  }

  /// Kanıt düzeyine göre rozet rengi
  Color _evidenceColor(String? evidence) {
    switch (evidence) {
      case 'strong':   return const Color(0xFFF43F5E);   // kırmızı
      case 'moderate': return const Color(0xFFF59E0B);   // turuncu
      case 'limited':  return const Color(0xFF64748B);   // gri
      default:         return Colors.white24;
    }
  }

  /// Kanıt düzeyi kısa etiketi
  String _evidenceLabel(String? evidence, String lang) {
    final tr = lang == 'tr';
    switch (evidence) {
      case 'strong':   return tr ? 'GÜÇLÜ KANIT' : 'STRONG';
      case 'moderate': return tr ? 'ORTA KANIT' : 'MODERATE';
      case 'limited':  return tr ? 'SINIRLI' : 'LIMITED';
      default:         return '';
    }
  }

  /// Riskleri kanıt gücüne göre sırala: strong > moderate > limited
  List<RiskIngredient> _sortedRisks(List<RiskIngredient> risks) {
    int rank(String? e) => e == 'strong' ? 0 : (e == 'moderate' ? 1 : 2);
    final list = List<RiskIngredient>.from(risks);
    list.sort((a, b) {
      final cmp = rank(a.evidence).compareTo(rank(b.evidence));
      if (cmp != 0) return cmp;
      return b.ewgScore.compareTo(a.ewgScore); // aynı kanıtta yüksek EWG önce
    });
    return list;
  }

  /// Kullanıcının alerjen profiliyle ürünün alerjenleri kesişiyorsa kırmızı uyarı
  List<Widget> _buildAllergenAlert(Product p) {
    if (_userAllergens.isEmpty || p.allergens == null) return [];
    final matches = p.allergens!
        .where((a) => _userAllergens.contains(a.toLowerCase().trim()))
        .toSet()
        .toList();
    if (matches.isEmpty) return [];
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626).withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.no_accounts_rounded, color: Color(0xFFFCA5A5), size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _lang == 'tr'
                  ? 'ALERJEN UYARISI — bu ürün senin alerjenlerini içeriyor!'
                  : 'ALLERGEN ALERT — contains your allergens!',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w800, fontSize: 14),
            )),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: matches.map((m) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(m.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            )).toList(),
          ),
        ]),
      ),
    ];
  }

  void _showNutriInfo(BuildContext context) {
    final isTr = _lang == 'tr';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF132720),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tutamaç
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                isTr ? '📊 Nutri-Score Nasıl Hesaplanır?' : '📊 How is Nutri-Score Calculated?',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              Text(
                isTr
                    ? 'Nutri-Score, besin değerlerine göre A\'dan E\'ye kadar bir skor verir. Bu skor, olumsuz ve olumlu besinlerin puanlanmasıyla hesaplanır.'
                    : 'Nutri-Score assigns a grade from A to E based on nutritional values, calculated by scoring negative and positive nutrients.',
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 20),

              Text(
                isTr ? '📊 Bu Ürün İçin Nutri-Score Hesabı' : '📊 Nutri-Score Calculation For This Product',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isTr
                    ? 'Besinler puanlanır, olumsuzlardan olumluları çıkarınca toplam puan çıkar. Puana göre A-E sınıfı verilir.'
                    : 'Nutrients are scored; subtracting positives from negatives gives the total. Grade A–E is assigned based on total.',
                style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),

              // ─── Bu ürünün gerçek değerleri ───────────────────
              if (widget.product.nutriBreakdown != null) ...[
                // Olumsuz besinler (puan artar)
                Text(
                  isTr ? '🔴 Olumsuz Besinler (puan artar ↑)' : '🔴 Negative Nutrients (score increases ↑)',
                  style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                _BreakdownRow(
                  label: isTr ? 'Enerji' : 'Energy',
                  value: widget.product.nutriBreakdown!.energy,
                  unit: 'kcal',
                  points: widget.product.nutriBreakdown!.energyPts,
                  isNegative: true,
                ),
                _BreakdownRow(
                  label: isTr ? 'Doymuş Yağ' : 'Saturated Fat',
                  value: widget.product.nutriBreakdown!.saturatedFat,
                  unit: 'g',
                  points: widget.product.nutriBreakdown!.saturatedFatPts,
                  isNegative: true,
                ),
                _BreakdownRow(
                  label: isTr ? 'Şeker' : 'Sugars',
                  value: widget.product.nutriBreakdown!.sugars,
                  unit: 'g',
                  points: widget.product.nutriBreakdown!.sugarsPts,
                  isNegative: true,
                ),
                _BreakdownRow(
                  label: isTr ? 'Sodyum' : 'Sodium',
                  value: widget.product.nutriBreakdown!.sodium,
                  unit: 'mg',
                  points: widget.product.nutriBreakdown!.sodiumPts,
                  isNegative: true,
                ),

                const SizedBox(height: 16),

                // Olumlu besinler (puan azalır)
                Text(
                  isTr ? '🟢 Olumlu Besinler (puan azalır ↓)' : '🟢 Positive Nutrients (score decreases ↓)',
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                _BreakdownRow(
                  label: isTr ? 'Protein' : 'Protein',
                  value: widget.product.nutriBreakdown!.proteins,
                  unit: 'g',
                  points: widget.product.nutriBreakdown!.proteinsPts,
                  isNegative: false,
                ),
                _BreakdownRow(
                  label: isTr ? 'Lif' : 'Fiber',
                  value: widget.product.nutriBreakdown!.fiber,
                  unit: 'g',
                  points: widget.product.nutriBreakdown!.fiberPts,
                  isNegative: false,
                ),

                // Toplam
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.product.nutriscoreColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.product.nutriscoreColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isTr ? 'TOPLAM PUAN' : 'TOTAL SCORE',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Row(children: [
                        Text(
                          '${widget.product.nutriscorePoints ?? '?'}',
                          style: TextStyle(
                            color: widget.product.nutriscoreColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: widget.product.nutriscoreColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Text(
                            (widget.product.nutriscoreGrade ?? '?').toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                          )),
                        ),
                      ]),
                    ],
                  ),
                ),
              ] else ...[
                // Breakdown yoksa genel açıklama
                _InfoBlock(
                  color: const Color(0xFFF43F5E),
                  icon: '🔴',
                  title: isTr ? 'Olumsuz (puan artar)' : 'Negative (increases score)',
                  items: isTr
                      ? ['Enerji (kalori)', 'Doymuş yağ', 'Şeker', 'Sodyum']
                      : ['Energy (calories)', 'Saturated fat', 'Sugars', 'Sodium'],
                ),
                const SizedBox(height: 12),
                _InfoBlock(
                  color: const Color(0xFF10B981),
                  icon: '🟢',
                  title: isTr ? 'Olumlu (puan azalır)' : 'Positive (reduces score)',
                  items: isTr
                      ? ['Lif', 'Protein', 'Meyve/sebze']
                      : ['Fiber', 'Protein', 'Fruits/vegetables'],
                ),
              ],

              const SizedBox(height: 16),
              Text(
                isTr
                    ? '* Nutri-Score Avrupa\'da kullanılan resmi beslenme etiketleme sistemidir.'
                    : '* Nutri-Score is an official nutritional labeling system used in Europe.',
                style: const TextStyle(color: Colors.white30, fontSize: 11, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Yardımcı Widget'lar ────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF132720),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _NutrimentRow extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final double multiplier;
  final String? subText;
  const _NutrimentRow(this.label, this.value, this.unit, [this.multiplier = 1.0, this.subText]);

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    final shown = value! * multiplier;
    // Yuvarlama: 100'den büyükse tamsayı, küçükse 1 ondalık
    final str = shown >= 100
        ? shown.toStringAsFixed(0)
        : shown.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$str $unit'),
            if (subText != null)
              TextSpan(
                text: '  ·  $subText',
                style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w400),
              ),
          ]),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 3'lü porsiyon toggle: 100g/100ml / Porsiyon / Paket
class _PortionToggle extends StatelessWidget {
  final int mode;           // 0=100g, 1=porsiyon, 2=paket
  final bool hasServing;
  final bool hasPackage;
  final ValueChanged<int> onChanged;
  final String lang;
  final String unit;        // "g" veya "ml" — içeceklerde ml

  const _PortionToggle({
    required this.mode,
    required this.hasServing,
    required this.hasPackage,
    required this.onChanged,
    required this.lang,
    this.unit = 'g',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          _toggleBtn(0, '100 $unit', alwaysEnabled: true),
          if (hasServing)
            _toggleBtn(1, lang == 'tr' ? 'Porsiyon' : 'Serving'),
          if (hasPackage)
            _toggleBtn(2, lang == 'tr' ? 'Paket' : 'Package'),
        ],
      ),
    );
  }

  Widget _toggleBtn(int idx, String label, {bool alwaysEnabled = false}) {
    final enabled = alwaysEnabled ||
        (idx == 1 && hasServing) ||
        (idx == 2 && hasPackage);
    final isActive = mode == idx;
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? () => onChanged(idx) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF10B981).withOpacity(0.28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isActive
                ? Border.all(color: const Color(0xFF10B981).withOpacity(0.85), width: 1.5)
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF2EE89A)
                  : (enabled ? Colors.white54 : Colors.white24),
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _NutriScaleBar extends StatelessWidget {
  final String? grade;
  const _NutriScaleBar({this.grade});

  @override
  Widget build(BuildContext context) {
    final grades = ['A', 'B', 'C', 'D', 'E'];
    final colors = [
      const Color(0xFF038141), const Color(0xFF85BB2F),
      const Color(0xFFFECB02), const Color(0xFFEE8100), const Color(0xFFE63E11),
    ];
    return Row(
      children: List.generate(5, (i) {
        final isActive = grades[i] == grade?.toUpperCase();
        return Expanded(
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colors[i].withOpacity(isActive ? 1.0 : 0.3),
              borderRadius: BorderRadius.circular(6),
              border: isActive ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Center(
              child: Text(grades[i],
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold, fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final Color color;
  final String icon;
  final String title;
  final List<String> items;

  const _InfoBlock({
    required this.color,
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$icon $title',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.arrow_right_rounded, color: color.withOpacity(0.7), size: 18),
              const SizedBox(width: 4),
              Text(item, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ]),
          )),
        ],
      ),
    );
  }
}

// Breakdown satırı: "Enerji  468 kcal  +5 puan"
class _BreakdownRow extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final int? points;
  final bool isNegative;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.points,
    required this.isNegative,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null && points == null) return const SizedBox.shrink();
    final ptColor = isNegative ? const Color(0xFFF43F5E) : const Color(0xFF10B981);
    final ptPrefix = isNegative ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ),
          if (value != null)
            Expanded(
              flex: 3,
              child: Text(
                '${value!.toStringAsFixed(1)} $unit',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          if (points != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ptColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ptColor.withOpacity(0.4)),
              ),
              child: Text(
                '$ptPrefix$points puan',
                style: TextStyle(color: ptColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
