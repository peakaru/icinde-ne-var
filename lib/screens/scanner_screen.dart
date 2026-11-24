import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/database_service.dart';
import '../services/system_service.dart';

class ScannerScreen extends StatefulWidget {
  final String? imagePath; // Galeriden gelirse dolu olur
  const ScannerScreen({super.key, this.imagePath});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // Barkod okumayı güçlendir: market barkodlarına odaklan, duplicate engelle
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 500,
    returnImage: false,
  );
  bool _scanned = false;
  String _lang = 'tr';

  @override
  void initState() {
    super.initState();
    DatabaseService.getSetting('lang').then((lang) {
      if (mounted && lang != null) setState(() => _lang = lang);
    });
    // Galeri fotoğrafı varsa analiz et
    if (widget.imagePath != null) {
      _analyzeImage(widget.imagePath!);
    }
  }

  Future<void> _analyzeImage(String path) async {
    BarcodeCapture? result;
    try {
      result = await _controller.analyzeImage(path);
    } catch (e) {
      // Desteklenmeyen/bozuk görsel: "bulunamadı" akışına düş, ekran
      // sonsuza kadar "Barkod aranıyor..."da kalmasın
      debugPrint('analyzeImage hatası: $e');
    }
    if (!mounted) return;
    if (result != null && result.barcodes.isNotEmpty) {
      final barcode = result.barcodes.first.rawValue;
      if (barcode != null) {
        Navigator.pop(context, barcode);
        return;
      }
    }
    // Barkod bulunamadı
    final msg = _lang == 'tr'
        ? 'Fotoğrafta barkod bulunamadı.'
        : 'No barcode found in the photo.';
    Navigator.pop(context, null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode != null) {
      _scanned = true;
      // Okunduğu hissedilsin. HapticFeedback sistemin dokunma geri bildirimi
      // ayarına bağlı ve çoğu telefonda hissedilmiyor; titreşim motoru doğrudan
      SystemService.vibrate().then((ok) {
        if (!ok) HapticFeedback.mediumImpact();
      });
      _controller.stop();
      Navigator.pop(context, barcode);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Galeri modu: sadece yükleniyor göster
    if (widget.imagePath != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF10B981)),
              const SizedBox(height: 20),
              Text(
                _lang == 'tr' ? 'Barkod aranıyor...' : 'Searching for barcode...',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // Kamera modu
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _lang == 'tr' ? 'Barkod Tara' : 'Scan Barcode',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error, child) => _CameraError(error: error, lang: _lang),
        // Çerçeve ve ipucu yalnızca kamera görüntüsü varken çizilir; hata
        // ekranındaki "Ayarları aç" düğmesinin üstünü kapatmasın
        overlayBuilder: (context, constraints) => SizedBox.fromSize(
          size: constraints.biggest,
          child: Stack(
            children: [
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: 280, height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF10B981), width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 60, left: 0, right: 0,
                child: Text(
                  _lang == 'tr'
                      ? 'Barkodu çerçeve içine alın'
                      : 'Align the barcode within the frame',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, backgroundColor: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kamera açılamadığında (çoğunlukla izin verilmediği için) gösterilen ekran
class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final String lang;
  const _CameraError({required this.error, required this.lang});

  @override
  Widget build(BuildContext context) {
    final tr = lang == 'tr';
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final title = denied
        ? (tr ? 'Kamera izni verilmedi' : 'Camera permission denied')
        : (tr ? 'Kamera açılamadı' : 'Could not open the camera');
    final body = denied
        ? (tr
            ? 'Barkod okumak için kameraya izin vermen gerekiyor. Ayarlar > İzinler > Kamera '
                'bölümünden izin verip bu ekranı yeniden açabilirsin. Kamerasız da galeriden '
                'barkod fotoğrafı seçebilir ya da ürünü adıyla arayabilirsin.'
            : 'Scanning needs camera access. Allow it under Settings > Permissions > Camera, '
                'then open this screen again. Without the camera you can still pick a barcode '
                'photo from the gallery or search by product name.')
        : (tr
            ? 'Kamera başka bir uygulama tarafından kullanılıyor olabilir. Geri dönüp tekrar dene; '
                'olmazsa galeriden barkod fotoğrafı seçebilirsin.'
            : 'Another app may be using the camera. Go back and try again, or pick a barcode '
                'photo from the gallery.');
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
              if (denied)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: () async {
                    final ok = await SystemService.openAppSettings();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr ? 'Ayarlar açılamadı.' : 'Could not open settings.'),
                      ));
                    }
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(tr ? 'Ayarları aç' : 'Open settings'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr ? 'Geri dön' : 'Go back', style: const TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
