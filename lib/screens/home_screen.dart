import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/system_service.dart';
import '../services/update_service.dart';
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
  // Sonuçlar gelince arama alanı ekranın üstüne kaydırılır; yoksa klavye
  // açıkken sonuçlar klavyenin arkasında kalıp görünmüyordu
  final GlobalKey _searchAreaKey = GlobalKey();
  bool _loading = false;
  String _lang = 'tr';

  // İsimle arama state'i
  List<SearchResult> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;
  // Her aramada artar; geç dönen eski bir yanıt yenisinin üstüne yazılmasın
  int _searchSeq = 0;

  // Ana ekranda son bakılan ürünler (geçmişin ilk 3'ü)
  List<Product> _recent = [];
  // GitHub'da yayımlanmış daha yeni sürüm (varsa)
  UpdateInfo? _update;
  // Sorgu 4 sn'yi geçerse "sunucu uyanıyor" uyarısı
  final Set<Object> _waits = {};  // süren sunucu istekleri
  Timer? _wakeTimer;
  int _wakeSeq = 0;
  int? _wakeWanted;   // gösterilmesi istenen uyarı
  int? _wakeVisible;  // şu an ekranda olan uyarı

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadLang();
    _loadRecent();
    _checkUpdate();
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
    _wakeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLang() async {
    final lang = await DatabaseService.getSetting('lang') ?? 'tr';
    if (mounted) setState(() => _lang = lang);
  }

  Future<void> _loadRecent() async {
    try {
      final hist = await DatabaseService.getHistory();
      if (mounted) setState(() => _recent = hist.take(3).toList());
    } catch (e) {
      debugPrint('Geçmiş okunamadı: $e');
    }
  }

  Future<void> _checkUpdate() async {
    final update = await UpdateService.check();
    if (mounted && update != null) setState(() => _update = update);
  }

  /// Hugging Face Space bir süre kullanılmayınca uyur; ilk istek uzun
  /// sürebilir. Bir istek 4 sn'yi geçerse kullanıcıya nedenini söyle.
  ///
  /// Her istek [_beginWait] ile bir jeton alır ve bitince [_endWait] ile
  /// bırakır (iki kez bırakmak zararsız). Uyarı, süren istek kalmayınca kalkar.
  Object _beginWait() {
    final token = Object();
    _waits.add(token);
    _wakeTimer ??= Timer(const Duration(seconds: 4), _showWakeHint);
    return token;
  }

  void _endWait(Object token) {
    if (!_waits.remove(token) || _waits.isNotEmpty) return;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _wakeWanted = null;
    if (_wakeVisible != null && mounted) {
      _wakeVisible = null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  /// Uyarı başka bir bildirimin arkasında sırada bekleyebilir; bu yüzden
  /// yalnızca gerçekten ekrandayken kapatılır, sıradayken iptal edildiyse
  /// göründüğü anda kendini kapatır (başka bildirimi yanlışlıkla kapatmamak için).
  void _showWakeHint() {
    _wakeTimer = null;
    if (!mounted || _waits.isEmpty || _wakeWanted != null) return;
    final id = ++_wakeSeq;
    _wakeWanted = id;
    final messenger = ScaffoldMessenger.of(context);
    messenger
        .showSnackBar(SnackBar(
          content: Text(
            _lang == 'tr'
                ? 'Sunucu uyanıyor, ilk sorgu yarım dakikayı bulabilir…'
                : 'The server is waking up; the first request can take up to half a minute…',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF1A3A28),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 30),
          onVisible: () {
            if (_wakeWanted == id) {
              _wakeVisible = id;
            } else {
              messenger.hideCurrentSnackBar(); // sırada beklerken iptal edildi
            }
          },
        ))
        .closed
        .then((_) {
          if (_wakeVisible == id) _wakeVisible = null;
          if (_wakeWanted == id) _wakeWanted = null;
        });
  }

  void _revealSearchResults() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _searchAreaKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _openUpdate() async {
    final url = _update?.url;
    if (url == null) return;
    final ok = await SystemService.openUrl(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_lang == 'tr' ? 'Bağlantı açılamadı: $url' : 'Could not open the link: $url'),
      ));
    }
  }

  Future<void> _openScanner() async {
    final barcode = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (barcode != null) _lookupBarcode(barcode);
  }

  void _openHistory() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))
        .then((_) => _loadRecent());
  }

  void _openProduct(Product p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)))
        .then((_) => _loadRecent());
  }

  /// Barkod veritabanında yok: nedenini ve yapılabilecekleri anlatan sayfa
  void _showNotFound(String barcode) {
    final tr = _lang == 'tr';
    var copied = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF132720),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Icon(Icons.search_off_rounded, color: Color(0xFFFBBF24), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr ? 'Bu ürün veritabanımızda yok' : 'This product is not in our database',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              StatefulBuilder(builder: (ctx, setSheet) {
                return Semantics(
                  button: true,
                  label: tr ? 'Barkodu kopyala' : 'Copy barcode',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: barcode));
                      setSheet(() => copied = true);
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(barcode, style: const TextStyle(color: Colors.white54, fontSize: 15)),
                      ),
                      const SizedBox(width: 6),
                      Icon(copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 14, color: copied ? const Color(0xFF2EE89A) : Colors.white24),
                      if (copied) ...[
                        const SizedBox(width: 4),
                        Text(tr ? 'kopyalandı' : 'copied',
                            style: const TextStyle(color: Color(0xFF2EE89A), fontSize: 12)),
                      ],
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Text(
                tr
                    ? 'Barkod doğru okunduysa bu ürün ne veritabanımızda ne de Open Food Facts\'te '
                        'bulunamadı. Ürünü adıyla aramayı dene: marketlerden derlenen kayıtların bir '
                        'kısmında barkod bulunmuyor, ürün o kayıtlar arasında olabilir.'
                    : 'If the barcode was read correctly, this product could not be found in our '
                        'database or in Open Food Facts. Try searching by name: some records collected '
                        'from supermarkets have no barcode, and the product may be one of them.',
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _barcodeController.clear();
                  setState(() => _searchResults = []);
                  _searchFocus.requestFocus();
                },
                icon: const Icon(Icons.search_rounded),
                label: Text(tr ? 'İsimle ara' : 'Search by name'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openScanner();
                },
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(tr ? 'Tekrar tara' : 'Scan again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Girdi değişince: rakamsa barkod modu (bekleme yok),
  /// harf varsa debounce'lu isim araması
  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final v = value.trim();

    // Sadece rakam → barkod modu, arama sonuçlarını temizle
    if (v.isEmpty || RegExp(r'^\d+$').hasMatch(v)) {
      _searchSeq++; // yoldaki arama yanıtı artık geçersiz
      if (mounted) setState(() { _searchResults = []; _searching = false; });
      return;
    }

    // Harf varsa → isim araması (400ms debounce)
    if (v.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(v);
    });
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_searchSeq;
    bool isCurrent() => mounted && seq == _searchSeq;
    if (mounted) setState(() => _searching = true);
    final wait = _beginWait();
    try {
      final results = await SearchService.search(query, limit: 8);
      if (isCurrent()) {
        setState(() => _searchResults = results);
        if (results.isNotEmpty) _revealSearchResults();
      }
    } on RateLimitException {
      if (mounted && seq == _searchSeq) {
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
      if (isCurrent()) setState(() => _searchResults = []);
    } finally {
      _endWait(wait);
      if (isCurrent()) setState(() => _searching = false);
    }
  }

  /// Arama sonucuna tıklayınca: barkodla tam lookup → detay ekranı
  Future<void> _openSearchResult(SearchResult r) async {
    if (_loading) return; // çift dokunuş iki detay ekranı açmasın
    if (mounted) setState(() => _loading = true);
    final wait = _beginWait();
    try {
      final result = await LookupService.lookup(r.barcode);
      _endWait(wait);
      final product = result.product;
      await DatabaseService.addToHistory(product);
      _loadRecent();
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ));
    } catch (e) {
      _endWait(wait);
      if (!mounted) return;
      if (e is! ProductNotFoundException) {
        _showLookupError(e);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_lang == 'tr' ? 'Ürün açılamadı.' : 'Could not open product.',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A3A28),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      _endWait(wait);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _lookupBarcode(String barcode, {String? imagePath}) async {
    if (barcode.isEmpty || _loading) return; // çift dokunuş iki sorgu başlatmasın
    setState(() => _loading = true);
    final wait = _beginWait();
    try {
      final result = await LookupService.lookup(barcode);
      _endWait(wait);
      final product = result.product;
      await DatabaseService.addToHistory(product);
      _loadRecent();
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
      _endWait(wait);
      if (!mounted) return;
      _showLookupError(e, barcode: barcode);
    } finally {
      _endWait(wait);
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Sorgu hatasını türüne göre anlat: "ürün yok" ile "bağlantı yok" ya da
  /// "sunucu yanıt vermiyor" aynı şey değil.
  void _showLookupError(Object e, {String? barcode}) {
    final tr = _lang == 'tr';
    String? message;
    if (e is RateLimitException) {
      message = tr
          ? 'Çok hızlı tarama yaptın — ~1 dakika sonra tekrar dene.'
          : 'Scanning too fast — try again in ~1 minute.';
    } else if (e is NetworkException) {
      message = tr
          ? 'İnternet bağlantısı yok ya da sunucuya ulaşılamadı. Daha önce taradığın ürünler çevrimdışı da açılır.'
          : 'No internet connection or the server is unreachable. Products you scanned before also open offline.';
    } else if (e is InvalidBarcodeException) {
      message = tr
          ? 'Bu bir ürün barkodu gibi görünmüyor (8–14 haneli olmalı).'
          : "This doesn't look like a product barcode (it should have 8–14 digits).";
    } else if (e is! ProductNotFoundException) {
      message = tr
          ? 'Sunucu şu an yanıt vermiyor. Biraz sonra tekrar dene.'
          : 'The server is not responding right now. Please try again shortly.';
    }
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF3A2A1A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    // Ürün veritabanında yok → nedenini anlatan sayfa (isimle ara / tekrar tara)
    if (barcode != null) {
      _showNotFound(barcode);
      return;
    }
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
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final barcode = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => ScannerScreen(imagePath: image.path)));
    if (barcode != null) _lookupBarcode(barcode, imagePath: image.path);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // Klavye açıkken alttaki imza satırı gizlenir; sonuçlara yer kalsın
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

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
                              // Logo (büyük yazı tipinde sığmazsa küçülür)
                              Flexible(child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (_, __) {
                                  final glow = 0.15 + _pulseController.value * 0.2;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      color: const Color(0xFF0F2A1E),
                                      border: Border.all(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF10B981).withValues(alpha: glow),
                                          blurRadius: 30,
                                          spreadRadius: -4,
                                        ),
                                      ],
                                    ),
                                    child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                                    ])),
                                  );
                                },
                              )),
                              _GlassIconBtn(
                                icon: Icons.star_rounded,
                                color: const Color(0xFFFBBF24),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                              ),
                            ],
                          ),

                          // ── Yeni sürüm ──────────────────────────
                          if (_update != null) ...[
                            const SizedBox(height: 16),
                            _UpdateCard(
                              update: _update!,
                              lang: _lang,
                              onOpen: _openUpdate,
                              onDismiss: () {
                                UpdateService.dismiss(_update!.version);
                                setState(() => _update = null);
                              },
                            ),
                          ],

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
                            onTap: _openScanner,
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
                            onTap: _openHistory,
                          ),

                          const SizedBox(height: 28),

                          // ── Ayırıcı ─────────────────────────────
                          Row(children: [
                            Expanded(child: Container(height: 1,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: 0.1),
                                  ]),
                                ))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(_lang == 'tr' ? 'VEYA' : 'OR',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.25),
                                      fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600)),
                            ),
                            Expanded(child: Container(height: 1,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Colors.white.withValues(alpha: 0.1),
                                    Colors.transparent,
                                  ]),
                                ))),
                          ]),

                          const SizedBox(height: 22),

                          // ── Akıllı Arama (barkod VEYA isim) ─────
                          Column(
                            key: _searchAreaKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lang == 'tr' ? 'Barkod veya Ürün Adı Yaz' : 'Barcode or Product Name',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
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
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.18)),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.06),
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 16),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide.none),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide(
                                              color: Colors.white.withValues(alpha: 0.08))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(
                                              color: Color(0xFF10B981), width: 1.5)),
                                    ),
                                    onChanged: _onQueryChanged,
                                    onSubmitted: (v) {
                                      final t = v.trim();
                                      // Sadece rakamsa barkod sorgusu (format kontrolü
                                      // ApiService'te), değilse arama zaten sonuç verdi
                                      if (RegExp(r'^\d+$').hasMatch(t)) {
                                        _lookupBarcode(t);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () {
                                    final t = _barcodeController.text.trim();
                                    if (RegExp(r'^\d+$').hasMatch(t)) {
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
                                        BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.35),
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
                                  child: _ProductTile(
                                    name: r.productName,
                                    brand: r.brand,
                                    grade: r.nutriscore,
                                    // Not açılınca OFF verisiyle hesaplanacak; listede
                                    // yerel veriden not göstermek çelişebilirdi
                                    note: r.gradeOnOpen
                                        ? (_lang == 'tr'
                                            ? 'Not, ürün açılınca hesaplanır'
                                            : 'Grade is calculated when opened')
                                        : null,
                                    onTap: () => _openSearchResult(r),
                                  ),
                                )),
                              ],
                            ],
                          ),

                          // ── Son bakılan ürünler ────────────────────
                          if (_recent.isNotEmpty && _searchResults.isEmpty && !_searching) ...[
                            const SizedBox(height: 26),
                            Row(children: [
                              Expanded(
                                child: Text(
                                  _lang == 'tr' ? 'Son baktıkların' : 'Recently viewed',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              GestureDetector(
                                onTap: _openHistory,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                  child: Text(_lang == 'tr' ? 'Tümü' : 'All',
                                      style: const TextStyle(color: Color(0xFF2EE89A),
                                          fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            ..._recent.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _ProductTile(
                                name: p.productName,
                                brand: p.brand ?? '',
                                grade: p.nutriscoreGrade,
                                onTap: () => _openProduct(p),
                              ),
                            )),
                          ],

                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ),

                  // ── Footer (altta; klavye açıkken gizli) ────────
                  if (!keyboardOpen) Padding(
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
                                color: const Color(0xFF10B981).withValues(alpha: opacity + 0.3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: opacity),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _lang == 'tr'
                                    ? 'İçinde Ne Var? • Sağlık için geliştirildi'
                                    : "What's Inside? • Built for health",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  fontSize: 11,
                                ),
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
          const Color(0xFF0D2D1E).withValues(alpha: 0.8),
          const Color(0xFF071310).withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, p1);

    // Alt sağ mavi glow
    final p2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.7, 0.6),
        radius: 0.5,
        colors: [
          const Color(0xFF0B1530).withValues(alpha: 0.4),
          const Color(0xFF071310).withValues(alpha: 0.0),
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
        splashColor: borderColor.withValues(alpha: 0.1),
        highlightColor: borderColor.withValues(alpha: 0.05),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: iconBg.withValues(alpha: 0.3)),
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
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              ],
            )),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.2), size: 16),
          ]),
        ),
      ),
    );
  }
}

// ── Ürün satırı (arama sonucu / son bakılan) ─────────────────────
class _ProductTile extends StatelessWidget {
  final String name;
  final String brand;
  final String? grade;   // "a".."e" ya da null (not yok)
  final String? note;    // ek bilgi satırı
  final VoidCallback onTap;

  const _ProductTile({
    required this.name,
    required this.brand,
    required this.grade,
    this.note,
    required this.onTap,
  });

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
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(children: [
            // Nutri-Score rozeti (hesaplanamadıysa jenerik ikon)
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: grade != null
                    ? nutriScoreColor(grade)
                    : const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: grade != null
                  ? Center(child: Text(
                      grade!.toUpperCase(),
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
                Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (brand.isNotEmpty)
                  Text(brand,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                if (note != null)
                  Text(note!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white30, fontSize: 11,
                          fontStyle: FontStyle.italic)),
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
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

// ── Yeni sürüm kartı ──────────────────────────────────────────────
class _UpdateCard extends StatelessWidget {
  final UpdateInfo update;
  final String lang;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _UpdateCard({
    required this.update,
    required this.lang,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tr = lang == 'tr';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F2A1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.system_update_rounded, color: Color(0xFF2EE89A), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr ? 'Yeni sürüm var: ${update.version}' : 'New version available: ${update.version}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(tr ? 'İndirme sayfasını açmak için dokun' : 'Tap to open the download page',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
            IconButton(
              tooltip: tr ? 'Bu sürümü gösterme' : 'Hide for this version',
              icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
              onPressed: onDismiss,
            ),
          ]),
        ),
      ),
    );
  }
}
