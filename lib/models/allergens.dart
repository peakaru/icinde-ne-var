/// Backend'in döndürdüğü alerjen anahtarları (backend/analysis.py → ALLERGENS)
/// ve arayüz etiketleri. Onboarding, ayarlar ve ürün detayı bu tek listeyi
/// kullanır; yeni bir alerjen eklenirse sadece burası güncellenir.
class Allergens {
  Allergens._();

  static const Map<String, String> _tr = {
    'süt': '🥛 Süt / Laktoz',
    'gluten': '🌾 Gluten',
    'yumurta': '🥚 Yumurta',
    'soya': '🫘 Soya',
    'kuruyemiş': '🥜 Kuruyemiş',
    'balık': '🐟 Balık',
    'kabuklu': '🦐 Kabuklu deniz ürünleri',
    'yumuşakça': '🦑 Yumuşakçalar',
    'susam': '🍯 Susam',
    'hardal': '🌭 Hardal',
    'kereviz': '🥬 Kereviz',
    'sülfit': '🍷 Sülfit',
    'lupin': '🌼 Acı bakla (lupin)',
  };

  static const Map<String, String> _en = {
    'süt': '🥛 Milk / Lactose',
    'gluten': '🌾 Gluten',
    'yumurta': '🥚 Egg',
    'soya': '🫘 Soy',
    'kuruyemiş': '🥜 Nuts',
    'balık': '🐟 Fish',
    'kabuklu': '🦐 Crustaceans',
    'yumuşakça': '🦑 Molluscs',
    'susam': '🍯 Sesame',
    'hardal': '🌭 Mustard',
    'kereviz': '🥬 Celery',
    'sülfit': '🍷 Sulphites',
    'lupin': '🌼 Lupin',
  };

  /// Seçim listeleri için anahtar → etiket haritası.
  static Map<String, String> labels(String lang) => lang == 'tr' ? _tr : _en;

  /// Tek bir anahtarın etiketi; bilinmeyen anahtar olduğu gibi gösterilir.
  static String label(String key, String lang) =>
      labels(lang)[key.toLowerCase().trim()] ?? key;
}
