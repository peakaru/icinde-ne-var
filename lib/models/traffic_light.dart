import 'product.dart';

enum NutrientLevel { low, medium, high }

/// Bir besin için ön etiket seviyesi ("Şeker yüksek").
class TrafficLight {
  final String nutrient; // sugars / saturated_fat / salt
  final double per100;   // g, 100 g ya da 100 ml başına
  final NutrientLevel level;
  const TrafficLight(this.nutrient, this.per100, this.level);
}

/// İngiltere gıda ajansının (FSA) ön etiket eşikleri, 100 g / 100 ml başına:
///
/// | besin       | yiyecek düşük / yüksek | içecek düşük / yüksek |
/// |-------------|------------------------|-----------------------|
/// | şeker       | ≤ 5    / > 22,5        | ≤ 2,5  / > 11,25      |
/// | doymuş yağ  | ≤ 1,5  / > 5           | ≤ 0,75 / > 2,5        |
/// | tuz         | ≤ 0,3  / > 1,5         | ≤ 0,3  / > 0,75       |
///
/// Arası "orta". Kendi yorumumuz değil, yayımlanmış eşikler. Tuz, sodyumdan
/// (mg × 2,5 / 1000) hesaplanır.
///
/// Gösterilmez: besin değeri yoksa, ürün grubu bilinmiyorsa (içecek mi
/// yiyecek mi belli değil) ya da kayıtlı değerler tutarsızsa (ör. porsiyon
/// başına girilmiş).
List<TrafficLight> trafficLights(Product p) {
  final nb = p.nutriBreakdown;
  final category = p.nutriscoreCategory;
  if (nb == null || category == null || p.nutriscoreUnavailableReason == 'implausible') {
    return const [];
  }
  final drink = category == 'beverage' || category == 'water';

  NutrientLevel level(double v, double low, double high) =>
      v <= low ? NutrientLevel.low : (v > high ? NutrientLevel.high : NutrientLevel.medium);

  final out = <TrafficLight>[];
  final sugars = nb.sugars;
  if (sugars != null) {
    out.add(TrafficLight('sugars', sugars,
        drink ? level(sugars, 2.5, 11.25) : level(sugars, 5, 22.5)));
  }
  final satFat = nb.saturatedFat;
  if (satFat != null) {
    out.add(TrafficLight('saturated_fat', satFat,
        drink ? level(satFat, 0.75, 2.5) : level(satFat, 1.5, 5)));
  }
  final sodium = nb.sodium;
  if (sodium != null) {
    final salt = sodium * 2.5 / 1000;
    out.add(TrafficLight('salt', salt, drink ? level(salt, 0.3, 0.75) : level(salt, 0.3, 1.5)));
  }
  return out;
}

/// "Şeker yüksek" / "High sugar"
String trafficLightLabel(TrafficLight t, String lang) {
  final tr = lang == 'tr';
  final name = switch (t.nutrient) {
    'sugars' => tr ? 'Şeker' : 'sugar',
    'saturated_fat' => tr ? 'Doymuş yağ' : 'sat. fat',
    _ => tr ? 'Tuz' : 'salt',
  };
  final lvl = switch (t.level) {
    NutrientLevel.high => tr ? 'yüksek' : 'High',
    NutrientLevel.medium => tr ? 'orta' : 'Medium',
    NutrientLevel.low => tr ? 'düşük' : 'Low',
  };
  return tr ? '$name $lvl' : '$lvl $name';
}
