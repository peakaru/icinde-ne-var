import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/compare_store.dart';
import '../services/database_service.dart';
import 'product_detail_screen.dart';

/// İki ürünü yan yana karşılaştırır: NS, besinler (100g), risk sayıları.
/// CompareStore'daki 2 ürünle açılır.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String _lang = 'tr';

  @override
  void initState() {
    super.initState();
    DatabaseService.getSetting('lang').then((lang) {
      if (mounted) setState(() => _lang = lang ?? 'tr');
    });
  }

  static const _gradeColors = {
    'A': Color(0xFF038141), 'B': Color(0xFF85BB2F), 'C': Color(0xFFFECB02),
    'D': Color(0xFFEE8100), 'E': Color(0xFFE63E11),
  };

  static int _gradeIdx(String? g) => 'ABCDE'.indexOf((g ?? '?').toUpperCase());

  @override
  Widget build(BuildContext context) {
    final items = CompareStore.items;
    final a = items[0];
    final b = items[1];

    // Daha sağlıklı: NS harfi önde olan (A=0 en iyi)
    final aIdx = _gradeIdx(a.nutriscoreGrade);
    final bIdx = _gradeIdx(b.nutriscoreGrade);
    final winner = aIdx < bIdx ? a : (bIdx < aIdx ? b : null);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F1A),
        foregroundColor: Colors.white,
        title: Text(
          _lang == 'tr' ? '⚖️ Karşılaştırma' : '⚖️ Compare',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              CompareStore.clear();
              Navigator.pop(context);
            },
            child: Text(
              _lang == 'tr' ? 'Temizle' : 'Clear',
              style: const TextStyle(color: Color(0xFFF43F5E)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Ürün başlıkları ───
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _ProductHeader(p: a, lang: _lang, isWinner: winner == a, onTap: () => _open(a))),
                const SizedBox(width: 10),
                Expanded(child: _ProductHeader(p: b, lang: _lang, isWinner: winner == b, onTap: () => _open(b))),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Besin satırları (100g bazlı, düşük=yeşil mantığına göre) ───
            _CompareRow(
              label: _lang == 'tr' ? 'Enerji' : 'Energy',
              aVal: a.nutriBreakdown?.energy, bVal: b.nutriBreakdown?.energy,
              unit: 'kcal', lowerIsBetter: true, lang: _lang,
            ),
            _CompareRow(
              label: _lang == 'tr' ? 'Şeker' : 'Sugars',
              aVal: a.nutriBreakdown?.sugars, bVal: b.nutriBreakdown?.sugars,
              unit: 'g', lowerIsBetter: true, lang: _lang,
            ),
            _CompareRow(
              label: _lang == 'tr' ? 'Doymuş Yağ' : 'Sat. Fat',
              aVal: a.nutriBreakdown?.saturatedFat, bVal: b.nutriBreakdown?.saturatedFat,
              unit: 'g', lowerIsBetter: true, lang: _lang,
            ),
            _CompareRow(
              label: _lang == 'tr' ? 'Sodyum' : 'Sodium',
              aVal: a.nutriBreakdown?.sodium, bVal: b.nutriBreakdown?.sodium,
              unit: 'mg', lowerIsBetter: true, lang: _lang,
            ),
            _CompareRow(
              label: _lang == 'tr' ? 'Protein' : 'Protein',
              aVal: a.nutriBreakdown?.proteins, bVal: b.nutriBreakdown?.proteins,
              unit: 'g', lowerIsBetter: false, lang: _lang,
            ),
            _CompareRow(
              label: _lang == 'tr' ? 'Lif' : 'Fiber',
              aVal: a.nutriBreakdown?.fiber, bVal: b.nutriBreakdown?.fiber,
              unit: 'g', lowerIsBetter: false, lang: _lang,
            ),
            _CompareRow(
              label: _lang == 'tr' ? '⚠️ Riskli içerik' : '⚠️ Risky ingredients',
              aCount: a.foundRisks?.length, bCount: b.foundRisks?.length,
              lowerIsBetter: true, lang: _lang,
            ),

            const SizedBox(height: 12),
            Text(
              _lang == 'tr' ? 'Değerler 100 g/ml başınadır.' : 'Values are per 100 g/ml.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  void _open(Product p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)));
  }
}

// ─── Ürün başlığı: NS rozeti + isim + kazanan bandı ───
class _ProductHeader extends StatelessWidget {
  final Product p;
  final String lang;
  final bool isWinner;
  final VoidCallback onTap;

  const _ProductHeader({required this.p, required this.lang, required this.isWinner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final grade = (p.nutriscoreGrade ?? '?').toUpperCase();
    final color = _CompareScreenState._gradeColors[grade] ?? const Color(0xFF64748B);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWinner ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFF132720),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isWinner ? const Color(0xFF10B981).withOpacity(0.6) : Colors.white.withOpacity(0.07),
            width: isWinner ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            if (isWinner)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  lang == 'tr' ? '✓ DAHA İYİ SEÇİM' : '✓ BETTER CHOICE',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(grade,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26))),
            ),
            const SizedBox(height: 8),
            Text(p.productName,
                maxLines: 3, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            if ((p.brand ?? '').isNotEmpty)
              Text(p.brand!,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─── Karşılaştırma satırı: etiket ortada, iki değer yanda ───
class _CompareRow extends StatelessWidget {
  final String label;
  final double? aVal;
  final double? bVal;
  final int? aCount;
  final int? bCount;
  final String unit;
  final bool lowerIsBetter;
  final String lang;

  const _CompareRow({
    required this.label,
    required this.lowerIsBetter,
    required this.lang,
    this.aVal, this.bVal,
    this.aCount, this.bCount,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    // Sayısal değer (risk sayacı da sayıya çevrilir)
    final va = aCount ?? aVal;
    final vb = bCount ?? bVal;

    String fmt(v) {
      if (v == null) return '—';
      if (v is double) {
        if (v >= 100) return v.toStringAsFixed(0);
        return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
      }
      return v.toString();
    }

    // Kazanan taraf (null'lar yarışmaz)
    final double? na = va is num ? va.toDouble() : null;
    final double? nb = vb is num ? vb.toDouble() : null;
    final bool? aWins = (na != null && nb != null && na != nb)
        ? (lowerIsBetter ? na < nb : na > nb)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF132720),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // A değeri
          Expanded(
            child: Text(
              unit.isEmpty ? fmt(va) : '${fmt(va)} $unit',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: aWins == true ? const Color(0xFF2EE89A) : (aWins == false ? Colors.white38 : Colors.white70),
                fontSize: 15,
                fontWeight: aWins == true ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          // Etiket
          Expanded(
            flex: 2,
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          // B değeri
          Expanded(
            child: Text(
              unit.isEmpty ? fmt(vb) : '${fmt(vb)} $unit',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: aWins == false ? const Color(0xFF2EE89A) : (aWins == true ? Colors.white38 : Colors.white70),
                fontSize: 15,
                fontWeight: aWins == false ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
