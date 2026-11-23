import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'product_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Product> _favorites = [];
  String _lang = 'tr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final favs = await DatabaseService.getFavorites();
    final lang = await DatabaseService.getSetting('lang') ?? 'tr';
    if (!mounted) return;
    setState(() { _favorites = favs; _lang = lang; });
  }

  Future<void> _removeFav(String barcode) async {
    await DatabaseService.removeFavorite(barcode);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F1A),
        foregroundColor: Colors.white,
        title: Text(
          _lang == 'tr' ? '⭐ Favorilerim' : '⭐ My Favorites',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _favorites.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_outline_rounded, color: Colors.white24, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _lang == 'tr' ? 'Henüz favori eklenmedi' : 'No favorites yet',
                    style: const TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _favorites.length,
              itemBuilder: (ctx, i) {
                final p = _favorites[i];
                return _ProductTile(
                  product: p,
                  lang: _lang,
                  trailing: IconButton(
                    icon: const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                    onPressed: () => _removeFav(p.barcode),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
                  ).then((_) => _load()),
                );
              },
            ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final String lang;
  final Widget trailing;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.lang,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF132720),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            // Nutri-Score badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: product.nutriscoreColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  (product.nutriscoreGrade ?? '?').toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Barkoda tıkla → kopyala
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: product.barcode));
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(lang == 'tr'
                            ? '📋 Barkod kopyalandı: ${product.barcode}'
                            : '📋 Barcode copied: ${product.barcode}'),
                        duration: const Duration(seconds: 2),
                      ));
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(product.barcode,
                                style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.copy_rounded, size: 12, color: Colors.white24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
