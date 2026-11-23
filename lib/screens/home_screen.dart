import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import 'scanner_screen.dart';
import 'product_detail_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _loading = false;
  String _lang = 'tr';

  // İsimle arama state'i
  List<SearchResult> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadLang();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _barcodeController.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadLang() async {
    final lang = await DatabaseService.getSetting('lang') ?? 'tr';
    if (mounted) setState(() => _lang = lang);
  }

  /// Girdi değişince: rakamsa barkod modu (bekleme yok),
  /// harf varsa debounce'lu isim araması
  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final v = value.trim();

    // Sadece rakam → barkod modu, arama sonuçlarını temizle
    if (v.isEmpty || RegExp(r'^\d+$').hasMatch(v)) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }

    // Harf varsa → isim araması (400ms debounce)
    if (v.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(v);
    });
  }

  Future<void> _runSearch(String query) async {
    if (mounted) setState(() => _searching = true);
    try {
      final results = await SearchService.search(query, limit: 8);
      if (mounted) setState(() => _searchResults = results);
    } on RateLimitException {
      if (mounted) {
        setState(() => _searchResults = []);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _lang == 'tr'
                ? 'Çok hızlı arama yaptın — ~1 dakika sonra tekrar dene.'
                : 'Searching too fast — try again in ~1 minute.',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF3A2A1A),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Arama sonucuna tıklayınca: barkodla tam lookup → detay ekranı
  Future<void> _openSearchResult(SearchResult r) async {
    if (mounted) setState(() => _loading = true);
    try {
      final result = await LookupService.lookup(r.barcode);
      final product = result.product;
      await DatabaseService.addToHistory(product);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_lang == 'tr' ? 'Ürün açılamadı.' : 'Could not open product.',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A3A28),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _lookupBarcode(String barcode, {String? imagePath}) async {
    if (barcode.isEmpty) return;
    setState(() => _loading = true);
    try {
      final result = await LookupService.lookup(barcode);
      final product = result.product;
      await DatabaseService.addToHistory(product);
      if (!mounted) return;
      // Çevrimdışı cache'ten geldiyse bilgilendir
      if (result.fromCache) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _lang == 'tr' ? '📡 Çevrimdışı — kayıtlı veri gösteriliyor' : '📡 Offline — showing cached data',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF3A2A1A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product, imagePath: imagePath),
      ));
    } catch (e) {
      if (!mounted) return;
      final isRateLimit = e is RateLimitException || e.toString().contains('RateLimitException');
      if (isRateLimit) {
        // Rate limit — geçici durum, ürün yok değil
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _lang == 'tr'
                ? 'Çok hızlı tarama yaptın — ~1 dakika sonra tekrar dene.'
                : 'Scanning too fast — try again in ~1 minute.',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF3A2A1A),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      // Ürün veritabanında yok → isimle aramaya yönlendir
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _lang == 'tr'
              ? 'Bu barkod veritabanımızda yok. İsmiyle aramayı dene!'
              : 'This barcode is not in our database. Try searching by name!',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF1A3A28),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: _lang == 'tr' ? 'İsimle Ara' : 'Search Name',
          textColor: const Color(0xFF2EE89A),
          onPressed: () {
            // Barkod yazısını temizle, arama alanına odaklan
            _barcodeController.clear();
            setState(() => _searchResults = []);
            _searchFocus.requestFocus();
          },
        ),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final barcode = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => ScannerScreen(imagePath: image.path)));
    if (barcode != null) _lookupBarcode(barcode, imagePath: image.path);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF071310),
        body: Stack(
          children: [
            // ── Arka plan gradyanı ───────────────────────────────
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => CustomPaint(
                  painter: _BgPainter(_pulseController.value),
                ),
              ),
            ),

            // ── İçerik ───────────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Scrollable üst kısım
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),

                          // ── Üst bar ─────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _GlassIconBtn(
                                icon: Icons.settings_outlined,
                                onTap: () async {
                                  await Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                                  _loadLang();
                                },
                              ),
                              // Logo
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (_, __) {
                                  final glow = 0.15 + _pulseController.value * 0.2;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      color: const Color(0xFF0F2A1E),
                                      border: Border.all(
                                        color: const Color(0xFF10B981).withOpacity(0.35),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF10B981).withOpacity(glow),
                                          blurRadius: 30,
                                          spreadRadius: -4,
                                        ),
                                      ],
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Image.asset('assets/images/logo.png', height: 48, width: 48),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_lang == 'tr' ? 'İÇİNDE' : "WHAT'S", style: const TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.w900,
                                            fontSize: 15, height: 1.2,
                                          )),
                                          Text(_lang == 'tr' ? 'NE VAR?' : 'INSIDE?', style: const TextStyle(
                                            color: Color(0xFF2EE89A), fontWeight: FontWeight.w900,
                                            fontSize: 15, height: 1.2,
                                          )),
                                        ],
                                      ),
                                    ]),
                                  );
                                },
                              ),
                              _GlassIconBtn(
                                icon: Icons.star_rounded,
                                color: const Color(0xFFFBBF24),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                              ),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // ── Hero başlık ──────────────────────────
                          Text(
                            _lang == 'tr' ? 'Ne yediğini' : "Know what",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF2EE89A), Color(0xFF10B981), Color(0xFF2EE89A)],
                            ).createShader(bounds),
                            child: Text(
                              _lang == 'tr' ? 'gerçekten bil' : "you're really eating",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),

                          const SizedBox(height: 44),

                          // ── Barkod Tara ──────────────────────────
                          _AeroCard(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [Color(0xFF0E3322), Color(0xFF0C4228)],
                            ),
                            borderColor: const Color(0xFF10B981),
                            icon: Icons.camera_alt_rounded,
                            iconBg: const Color(0xFF10B981),
                            title: _lang == 'tr' ? 'BARKOD TARA' : 'SCAN BARCODE',
                            subtitle: _lang == 'tr' ? 'Ürünün barkodunu kamerayla okut' : 'Point camera at barcode',
                            onTap: () async {
                              final barcode = await Navigator.push<String>(context,
                                  MaterialPageRoute(builder: (_) => const ScannerScreen()));
                              if (barcode != null) _lookupBarcode(barcode);
                            },
                          ),

                          const SizedBox(height: 12),

                          // ── Galeri ───────────────────────────────
                          _AeroCard(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [Color(0xFF101535), Color(0xFF191260)],
                            ),
                            borderColor: const Color(0xFF6366F1),
                            icon: Icons.photo_library_outlined,
                            iconBg: const Color(0xFF6366F1),
                            title: _lang == 'tr' ? 'BARKOD FOTOĞRAFI SEÇ' : 'PICK BARCODE PHOTO',
                            subtitle: _lang == 'tr' ? 'Galeriden barkod fotoğrafı seç' : 'Select from gallery',
                            onTap: _pickFromGallery,
                          ),

                          const SizedBox(height: 12),

                          // ── Geçmiş ──────────────────────────────
                          _AeroCard(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [Color(0xFF161616), Color(0xFF1E1E1E)],
                            ),
                            borderColor: Colors.white24,
                            icon: Icons.history_rounded,
                            iconBg: const Color(0xFF3A3A3A),
                            title: _lang == 'tr' ? 'SON TARAMALAR' : 'RECENT SCANS',
                            subtitle: _lang == 'tr' ? 'Geçmiş taramalarını gör' : 'View scan history',
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const HistoryScreen())),
                          ),

                          const SizedBox(height: 28),

                          // ── Ayırıcı ─────────────────────────────
                          Row(children: [
                            Expanded(child: Container(height: 1,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Colors.transparent,
                                    Colors.white.withOpacity(0.1),
                                  ]),
                                ))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(_lang == 'tr' ? 'VEYA' : 'OR',
                                  style: TextStyle(color: Colors.white.withOpacity(0.25),
                                      fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600)),
                            ),
                            Expanded(child: Container(height: 1,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Colors.white.withOpacity(0.1),
                                    Colors.transparent,
                                  ]),
                                ))),
                          ]),

                          const SizedBox(height: 22),

                          // ── Akıllı Arama (barkod VEYA isim) ─────
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lang == 'tr' ? 'Barkod veya Ürün Adı Yaz' : 'Barcode or Product Name',
                                style: TextStyle(color: Colors.white.withOpacity(0.5),
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: TextField(
                                    controller: _barcodeController,
                                    focusNode: _searchFocus,
                                    // Hem rakam hem harf kabul et (akıllı mod)
                                    keyboardType: TextInputType.text,
                                    style: const TextStyle(color: Colors.white, fontSize: 15),
                                    decoration: InputDecoration(
                                      hintText: _lang == 'tr'
                                          ? 'Barkod (869...) veya ürün adı (nutella)'
                                          : 'Barcode (869...) or name (nutella)',
                                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.18)),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.06),
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 16),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide.none),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide(
                                              color: Colors.white.withOpacity(0.08))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(
                                              color: Color(0xFF10B981), width: 1.5)),
                                    ),
                                    onChanged: _onQueryChanged,
                                    onSubmitted: (v) {
                                      final t = v.trim();
                                      // Sadece rakamsa barkod sorgusu, değilse arama zaten sonuç verdi
                                      if (RegExp(r'^\d{6,}$').hasMatch(t)) {
                                        _lookupBarcode(t);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () {
                                    final t = _barcodeController.text.trim();
                                    if (RegExp(r'^\d{6,}$').hasMatch(t)) {
                                      _lookupBarcode(t);
                                    } else if (t.length >= 2) {
                                      _runSearch(t);
                                    }
                                  },
                                  child: Container(
                                    width: 54, height: 54,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(color: const Color(0xFF10B981).withOpacity(0.35),
                                            blurRadius: 20, offset: const Offset(0, 5)),
                                      ],
                                    ),
                                    child: _loading
                                        ? const Center(child: SizedBox(width: 22, height: 22,
                                        child: CircularProgressIndicator(color: Colors.white,
                                            strokeWidth: 2.5)))
                                        : const Icon(Icons.search_rounded, color: Colors.white, size: 24),
                                  ),
                                ),
                              ]),

                              // ─── Arama sonuçları ──────────────────
                              if (_searching) ...[
                                const SizedBox(height: 10),
                                const Center(child: SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                        color: Color(0xFF10B981), strokeWidth: 2))),
                              ] else if (_searchResults.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                ..._searchResults.map((r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _SearchResultTile(
                                    result: r,
                                    onTap: () => _openSearchResult(r),
                                  ),
                                )),
                              ],
                            ],
                          ),

                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ),

                  // ── Footer (her zaman altta) ──────────────────
                  Padding(
                    padding: EdgeInsets.only(bottom: bottomPad + 16, top: 8),
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) {
                        final opacity = 0.15 + _pulseController.value * 0.15;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF10B981).withOpacity(opacity + 0.3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(opacity),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _lang == 'tr'
                                  ? 'İçinde Ne Var? • Sağlık için geliştirildi'
                                  : "What's Inside? • Built for health",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.22),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Arka plan ─────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF071310));

    // Üst yeşil glow
    final p1 = Paint()
      ..shader = RadialGradient(
        center: Alignment(0.0, -0.7 + t * 0.05),
        radius: 0.9,
        colors: [
          const Color(0xFF0D2D1E).withOpacity(0.8),
          const Color(0xFF071310).withOpacity(0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, p1);

    // Alt sağ mavi glow
    final p2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.7, 0.6),
        radius: 0.5,
        colors: [
          const Color(0xFF0B1530).withOpacity(0.4),
          const Color(0xFF071310).withOpacity(0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, p2);
  }

  @override
  bool shouldRepaint(_BgPainter old) => (old.t - t).abs() > 0.02;
}

// ── Aero kart ─────────────────────────────────────────────────────
class _AeroCard extends StatelessWidget {
  final LinearGradient gradient;
  final Color borderColor;
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AeroCard({
    required this.gradient,
    required this.borderColor,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: borderColor.withOpacity(0.1),
        highlightColor: borderColor.withOpacity(0.05),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor.withOpacity(0.2)),
          ),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: iconBg.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: iconBg.withOpacity(0.3)),
              ),
              child: Icon(icon, color: iconBg, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800,
                    fontSize: 15, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 12)),
              ],
            )),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.2), size: 16),
          ]),
        ),
      ),
    );
  }
}

// ── Arama sonuç satırı ────────────────────────────────────────────
class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(children: [
            // Nutri-Score rozeti (hesaplanamadıysa jenerik ikon)
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: result.nutriscore != null
                    ? result.nutriscoreColor
                    : const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: result.nutriscore != null
                  ? Center(child: Text(
                      result.nutriscore!.toUpperCase(),
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ))
                  : const Icon(Icons.inventory_2_rounded,
                      color: Color(0xFF10B981), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.productName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (result.brand.isNotEmpty)
                  Text(result.brand,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            )),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── Cam ikon butonu ───────────────────────────────────────────────
class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _GlassIconBtn({
    required this.icon,
    required this.onTap,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
