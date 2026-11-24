import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/format.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'product_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Product> _history = [];
  String _lang = 'tr';
  // Seçim modu: checkbox'larla belli kayıtları silme
  bool _selectMode = false;
  final Set<String> _selected = {};
  // Geçmişte arama (ad, marka, barkod)
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  /// Arama kutusuna uyan kayıtlar
  List<Product> get _visible {
    final q = foldForSearch(_query.trim());
    if (q.isEmpty) return _history;
    final words = q.split(RegExp(r'\s+'));
    return _history.where((p) {
      final hay = foldForSearch('${p.productName} ${p.brand ?? ''} ${p.barcode}');
      return words.every(hay.contains);
    }).toList();
  }

  void _onQueryChanged(String v) {
    setState(() {
      _query = v;
      // Görünmeyen kayıtlar seçili kalmasın; silinecekler hep ekranda olsun
      final visible = _visible.map((p) => p.barcode).toSet();
      _selected.retainWhere(visible.contains);
    });
  }

  Future<void> _load() async {
    final hist = await DatabaseService.getHistory();
    final lang = await DatabaseService.getSetting('lang') ?? 'tr';
    if (!mounted) return;
    setState(() { _history = hist; _lang = lang; });
  }

  void _enterSelectMode() {
    setState(() { _selectMode = true; _selected.clear(); });
  }

  void _exitSelectMode() {
    setState(() { _selectMode = false; _selected.clear(); });
  }

  void _toggleSelect(String barcode) {
    setState(() {
      if (_selected.contains(barcode)) {
        _selected.remove(barcode);
      } else {
        _selected.add(barcode);
      }
    });
  }

  void _toggleSelectAll() {
    final visible = _visible.map((p) => p.barcode).toList();
    setState(() {
      if (visible.every(_selected.contains)) {
        _selected.removeAll(visible);
      } else {
        _selected.addAll(visible);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132720),
        title: Text(_lang == 'tr' ? 'Kayıtları Sil' : 'Delete Entries',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          _lang == 'tr' ? '$n kayıt silinecek, emin misiniz?' : '$n entries will be deleted, are you sure?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_lang == 'tr' ? 'İptal' : 'Cancel',
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_lang == 'tr' ? 'Sil' : 'Delete',
                style: const TextStyle(color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.deleteHistoryItems(_selected.toList());
      _exitSelectMode();
      _load();
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132720),
        title: Text(_lang == 'tr' ? 'Geçmişi Temizle' : 'Clear History',
            style: const TextStyle(color: Colors.white)),
        content: Text(_lang == 'tr' ? 'Tüm geçmiş silinecek, emin misiniz?' : 'All history will be deleted, are you sure?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_lang == 'tr' ? 'İptal' : 'Cancel',
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_lang == 'tr' ? 'Sil' : 'Delete',
                style: const TextStyle(color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.clearHistory();
      _exitSelectMode();
      _load();
    }
  }

  void _copyBarcode(String barcode) {
    Clipboard.setData(ClipboardData(text: barcode));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_lang == 'tr' ? '📋 Barkod kopyalandı: $barcode' : '📋 Barcode copied: $barcode'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final allSelected = visible.isNotEmpty && visible.every((p) => _selected.contains(p.barcode));
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F1A),
        foregroundColor: Colors.white,
        title: Text(
          _selectMode
              ? (_lang == 'tr' ? 'Seç: ${_selected.length}' : 'Selected: ${_selected.length}')
              : (_lang == 'tr' ? '📜 Son Taramalar' : '📜 Recent Scans'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectMode) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                allSelected
                    ? (_lang == 'tr' ? 'Hiçbiri' : 'None')
                    : (_lang == 'tr' ? 'Tümünü Seç' : 'Select All'),
                style: const TextStyle(color: Color(0xFF2EE89A)),
              ),
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: Text(
                _lang == 'tr' ? 'Sil (${_selected.length})' : 'Delete (${_selected.length})',
                style: TextStyle(
                  color: _selected.isEmpty ? Colors.white24 : const Color(0xFFF43F5E),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: _exitSelectMode,
            ),
          ] else if (_history.isNotEmpty) ...[
            // Seçmeli temizleme: seç moduna geç
            TextButton(
              onPressed: _enterSelectMode,
              child: Text(
                _lang == 'tr' ? 'Seç' : 'Select',
                style: const TextStyle(color: Color(0xFF2EE89A)),
              ),
            ),
            TextButton(
              onPressed: _clearAll,
              child: Text(
                _lang == 'tr' ? 'Temizle' : 'Clear',
                style: const TextStyle(color: Color(0xFFF43F5E)),
              ),
            ),
          ],
        ],
      ),
      body: _history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, color: Colors.white24, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _lang == 'tr' ? 'Henüz tarama yapılmadı' : 'No scans yet',
                    style: const TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                ],
              ),
            )
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _queryController,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _lang == 'tr' ? 'Geçmişte ara: ad, marka, barkod' : 'Search history: name, brand, barcode',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _lang == 'tr' ? 'Temizle' : 'Clear',
                            icon: const Icon(Icons.close_rounded, color: Colors.white38),
                            onPressed: () {
                              _queryController.clear();
                              _onQueryChanged('');
                            },
                          ),
                    filled: true,
                    fillColor: const Color(0xFF132720),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF10B981)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _lang == 'tr' ? 'Aramana uyan kayıt yok' : 'No entries match your search',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 15),
                          ),
                        ),
                      )
                    : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: visible.length,
              itemBuilder: (ctx, i) {
                final p = visible[i];
                final isSelected = _selected.contains(p.barcode);
                return _HistoryTile(
                  // Süzülünce satırlar yer değiştirir; favori durumu ürünle kalsın
                  key: ValueKey(p.barcode),
                  product: p,
                  lang: _lang,
                  selectMode: _selectMode,
                  isSelected: isSelected,
                  onTap: () {
                    if (_selectMode) {
                      _toggleSelect(p.barcode);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
                      ).then((_) => _load());
                    }
                  },
                  onLongPress: !_selectMode ? _enterSelectMode : null,
                  onCopyBarcode: () => _copyBarcode(p.barcode),
                  onFavTap: () async {
                    final isFav = await DatabaseService.isFavorite(p.barcode);
                    if (isFav) {
                      await DatabaseService.removeFavorite(p.barcode);
                    } else {
                      await DatabaseService.addFavorite(p);
                    }
                    _load();
                  },
                );
              },
            ),
              ),
            ]),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  final Product product;
  final String lang;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onCopyBarcode;
  final VoidCallback onFavTap;

  const _HistoryTile({
    super.key,
    required this.product,
    required this.lang,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    required this.onCopyBarcode,
    required this.onFavTap,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    DatabaseService.isFavorite(widget.product.barcode).then((v) {
      if (mounted) setState(() => _isFav = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: widget.isSelected ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFF132720),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isSelected ? const Color(0xFF10B981).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            // Seçim modunda checkbox, normalde Nutri-Score rozeti
            if (widget.selectMode)
              GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    color: widget.isSelected ? const Color(0xFF10B981) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.isSelected ? const Color(0xFF10B981) : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: widget.isSelected
                      ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                      : null,
                ),
              )
            else ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.product.nutriscoreColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    (widget.product.nutriscoreGrade ?? '?').toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.product.productName,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  // Barkoda tıkla → kopyala (satır tıklaması detayı tetiklemesin)
                  GestureDetector(
                    onTap: widget.onCopyBarcode,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(widget.product.barcode,
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
            if (!widget.selectMode)
              IconButton(
                icon: Icon(
                  _isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFFBBF24),
                ),
                onPressed: () {
                  setState(() => _isFav = !_isFav);
                  widget.onFavTap();
                },
              ),
          ],
        ),
      ),
    );
  }
}
