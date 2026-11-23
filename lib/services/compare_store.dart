import '../models/product.dart';

/// Karşılaştırma sepeti — 2 ürün tutar, uygulama genelinde erişilir.
/// Provider'a gerek yok: statik, geçici bir seçim alanı.
class CompareStore {
  static final List<Product> _items = [];

  static List<Product> get items => List.unmodifiable(_items);

  static bool contains(String barcode) =>
      _items.any((p) => p.barcode == barcode);

  /// Ekler. Dönen değer: 0 = zaten ekli, 1 = ilk ürün eklendi, 2 = ikinci ürün
  /// eklendi (karşılaştırma ekranı açılabilir).
  static int add(Product p) {
    if (contains(p.barcode)) return 0;
    if (_items.length >= 2) _items.removeLast();
    _items.add(p);
    return _items.length;
  }

  static void remove(String barcode) =>
      _items.removeWhere((p) => p.barcode == barcode);

  static void clear() => _items.clear();

  /// Nutri-Score'u daha iyi olan ürün; notlar eşitse ya da biri bilinmiyorsa
  /// null (kazanan yok). Bilinmeyen not hiçbir zaman "daha sağlıklı" sayılmaz.
  static Product? healthier(Product a, Product b) {
    final ai = _gradeIndex(a.nutriscoreGrade);
    final bi = _gradeIndex(b.nutriscoreGrade);
    if (ai == null || bi == null || ai == bi) return null;
    return ai < bi ? a : b;
  }

  static int? _gradeIndex(String? grade) {
    final i = 'ABCDE'.indexOf((grade ?? '').toUpperCase());
    return (grade == null || grade.isEmpty || i < 0) ? null : i;
  }
}
