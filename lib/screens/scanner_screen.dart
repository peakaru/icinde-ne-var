import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/database_service.dart';

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
    final result = await _controller.analyzeImage(path);
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
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 280, height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF10B981), width: 3),
                borderRadius: BorderRadius.circular(16),
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
    );
  }
}
