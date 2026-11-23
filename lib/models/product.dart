import 'package:flutter/material.dart';

/// Resmi Nutri-Score paleti (A → E). Bilinmeyen not gri gösterilir.
const Map<String, Color> nutriScoreColors = {
  'A': Color(0xFF038141),
  'B': Color(0xFF85BB2F),
  'C': Color(0xFFFECB02),
  'D': Color(0xFFEE8100),
  'E': Color(0xFFE63E11),
};

Color nutriScoreColor(String? grade) =>
    nutriScoreColors[grade?.toUpperCase()] ?? const Color(0xFF64748B);

class RiskIngredient {
  final String name;
  final String? nameEn;   // İngilizce UI'da gösterilen ad (eski kayıtlarda null)
  final int ewgScore;
  final String risk;
  final String? riskEn;   // İngilizce açıklama (eski kayıtlarda null)
  // Kanıt-etiketli model (v3.0.0) — backend'den gelir, eski kayıtlarda null
  final String? evidence;  // limited / moderate / strong
  final String? color;     // green / yellow / orange / red
  final String? source;    // "EFSA 2021 güvenli bulmadı..." gibi kaynak açıklaması
  final String? sourceEn;  // İngilizce kaynak metni
  RiskIngredient({
    required this.name,
    required this.ewgScore,
    required this.risk,
    this.nameEn,
    this.riskEn,
    this.evidence,
    this.color,
    this.source,
    this.sourceEn,
  });
  factory RiskIngredient.fromJson(Map<String, dynamic> j) => RiskIngredient(
        name: j['name'] ?? '',
        ewgScore: j['ewg_score'] ?? 0,
        risk: j['risk'] ?? '',
        nameEn: j['name_en'],
        riskEn: j['risk_en'],
        evidence: j['evidence'],
        color: j['color'],
        source: j['source'],
        sourceEn: j['source_en'],
      );
}

class NutriBreakdown {
  final double? energy;     final int? energyPts;
  final double? sugars;     final int? sugarsPts;
  final double? saturatedFat; final int? saturatedFatPts;
  final double? sodium;     final int? sodiumPts;
  final double? proteins;   final int? proteinsPts;
  final double? fiber;      final int? fiberPts;

  NutriBreakdown({
    this.energy, this.energyPts,
    this.sugars, this.sugarsPts,
    this.saturatedFat, this.saturatedFatPts,
    this.sodium, this.sodiumPts,
    this.proteins, this.proteinsPts,
    this.fiber, this.fiberPts,
  });

  factory NutriBreakdown.fromJson(Map<String, dynamic> j) {
    double? val(String key) => (j[key]?['value'] as num?)?.toDouble();
    int? pts(String key) => (j[key]?['points'] as num?)?.toInt();
    return NutriBreakdown(
      energy: val('energy'),         energyPts: pts('energy'),
      sugars: val('sugars'),         sugarsPts: pts('sugars'),
      saturatedFat: val('saturated_fat'), saturatedFatPts: pts('saturated_fat'),
      sodium: val('sodium'),         sodiumPts: pts('sodium'),
      proteins: val('proteins'),     proteinsPts: pts('proteins'),
      fiber: val('fiber'),           fiberPts: pts('fiber'),
    );
  }
}

class Product {
  final String barcode;
  final String productName;
  final String? brand;
  final String? imageUrl;
  final bool dataWarning;

  // Nutri-Score
  final String? nutriscoreGrade;
  final int? nutriscorePoints;
  final NutriBreakdown? nutriBreakdown;

  // İçerikler
  final List<String>? allIngredients;
  final List<RiskIngredient>? foundRisks;
  final List<String>? allergens;
  final bool criticalSafetyRule;

  // Porsiyon/Paket bilgisi (v2.1.0)
  final double productQuantity;    // toplam paket (g veya ml)
  final double servingQuantity;    // 1 porsiyon (g veya ml)
  final String servingSizeText;    // ham text
  final String quantityInfo;       // özet ("200 g", "330 ml", "1 kase (40g)")
  final String quantitySource;     // "off" / "regex" / "unknown"
  final String quantityUnit;       // "g" (katı) veya "ml" (içecek) — UI toggle için

  // Veri kaynağı şeffaflığı (backend "source" alanı)
  // "Local Database" / "Open Food Facts" / "Local + OFF"
  final String dataSource;

  Product({
    required this.barcode,
    required this.productName,
    this.brand,
    this.imageUrl,
    this.dataWarning = false,
    this.nutriscoreGrade,
    this.nutriscorePoints,
    this.nutriBreakdown,
    this.allIngredients,
    this.foundRisks,
    this.allergens,
    this.criticalSafetyRule = false,
    this.productQuantity = 0,
    this.servingQuantity = 0,
    this.servingSizeText = '',
    this.quantityInfo = '',
    this.quantitySource = 'unknown',
    this.quantityUnit = 'g',
    this.dataSource = '',
  });

  /// Porsiyon modu kullanılabilir mi? (serving_quantity > 0)
  bool get hasServing => servingQuantity > 0;

  /// Paket modu kullanılabilir mi? (product_quantity > 0)
  bool get hasPackage => productQuantity > 0;

  factory Product.fromJson(Map<String, dynamic> json) {
    // nutri_score nested objesi
    final nutriScore = json['nutri_score'] as Map<String, dynamic>?;
    final breakdown = nutriScore?['breakdown'] as Map<String, dynamic>?;

    // found_risks listesi
    final risksRaw = json['found_risks'] as List<dynamic>?;
    final risks = risksRaw?.map((e) => RiskIngredient.fromJson(e as Map<String, dynamic>)).toList();

    // all_ingredients listesi
    final ingredientsRaw = json['all_ingredients'] as List<dynamic>?;
    final ingredients = ingredientsRaw?.map((e) => e.toString()).toList();

    // allergens listesi
    final allergensRaw = json['allergens'] as List<dynamic>?;
    final allergens = allergensRaw?.map((e) => e.toString()).toList();

    return Product(
      barcode: json['barcode'] ?? json['code'] ?? '',
      productName: json['product_name'] ?? 'Bilinmeyen Ürün',
      brand: json['brand'],
      imageUrl: json['image_url'],
      dataWarning: json['data_warning'] ?? false,
      nutriscoreGrade: nutriScore?['grade'] as String?,
      nutriscorePoints: (nutriScore?['points'] as num?)?.toInt(),
      nutriBreakdown: breakdown != null ? NutriBreakdown.fromJson(breakdown) : null,
      allIngredients: ingredients,
      foundRisks: risks,
      allergens: allergens,
      criticalSafetyRule: json['critical_safety_rule'] ?? false,
      // Porsiyon/paket (v2.1.0)
      productQuantity: (json['product_quantity'] as num?)?.toDouble() ?? 0,
      servingQuantity: (json['serving_quantity'] as num?)?.toDouble() ?? 0,
      servingSizeText: json['serving_size_text'] ?? '',
      quantityInfo: json['quantity_info'] ?? '',
      quantitySource: json['quantity_source'] ?? 'unknown',
      quantityUnit: json['quantity_unit'] ?? 'g',
      dataSource: json['source'] ?? '',
    );
  }

  Color get nutriscoreColor => nutriScoreColor(nutriscoreGrade);
}
