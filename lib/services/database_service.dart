import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'icinde_ne_var.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT UNIQUE NOT NULL,
            product_name TEXT NOT NULL,
            brand TEXT,
            nutriscore_grade TEXT,
            product_json TEXT,
            date_added TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE scan_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            product_name TEXT NOT NULL,
            brand TEXT,
            nutriscore_grade TEXT,
            product_json TEXT,
            scan_date TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE user_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE cached_products (
            barcode TEXT PRIMARY KEY,
            data_json TEXT NOT NULL,
            cached_date TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1/v2 → v3: product_json kolonu eklendi (tam veri)
        if (oldVersion < 3) {
          try { await db.execute('ALTER TABLE scan_history ADD COLUMN product_json TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE favorites ADD COLUMN product_json TEXT'); } catch (_) {}
        }
      },
    );
  }

  // Ürünü JSON'a çevir (tam veri) — Product.fromJson ile birebir geri okunabilmeli
  @visibleForTesting
  static String productToJson(Product p) => jsonEncode({
    'barcode': p.barcode,
    'product_name': p.productName,
    'brand': p.brand,
    'image_url': p.imageUrl,
    'data_warning': p.dataWarning,
    'nutri_score': p.nutriscoreGrade == null ? null : {
      'grade': p.nutriscoreGrade,
      'points': p.nutriscorePoints,
      'breakdown': p.nutriBreakdown == null ? null : {
        'energy':       {'value': p.nutriBreakdown!.energy, 'points': p.nutriBreakdown!.energyPts},
        'sugars':       {'value': p.nutriBreakdown!.sugars, 'points': p.nutriBreakdown!.sugarsPts},
        'saturated_fat':{'value': p.nutriBreakdown!.saturatedFat, 'points': p.nutriBreakdown!.saturatedFatPts},
        'sodium':       {'value': p.nutriBreakdown!.sodium, 'points': p.nutriBreakdown!.sodiumPts},
        'proteins':     {'value': p.nutriBreakdown!.proteins, 'points': p.nutriBreakdown!.proteinsPts},
        'fiber':        {'value': p.nutriBreakdown!.fiber, 'points': p.nutriBreakdown!.fiberPts},
      },
    },
    'found_risks': p.foundRisks?.map((r) => {
      'name': r.name,
      'name_en': r.nameEn,
      'ewg_score': r.ewgScore,
      'risk': r.risk,
      'risk_en': r.riskEn,
      'evidence': r.evidence,
      'color': r.color,
      'source': r.source,
      'source_en': r.sourceEn,
    }).toList(),
    'allergens': p.allergens,
    'all_ingredients': p.allIngredients,
    'critical_safety_rule': p.criticalSafetyRule,
    // Porsiyon/paket bilgisi (geçmişten bakınca toggle çalışsın)
    'product_quantity': p.productQuantity,
    'serving_quantity': p.servingQuantity,
    'serving_size_text': p.servingSizeText,
    'quantity_info': p.quantityInfo,
    'quantity_source': p.quantitySource,
    'quantity_unit': p.quantityUnit,
    'source': p.dataSource,
  });

  // JSON'dan ürün geri al
  static Product _fromRow(Map<String, dynamic> row) {
    if (row['product_json'] != null) {
      try {
        final json = jsonDecode(row['product_json'] as String) as Map<String, dynamic>;
        return Product.fromJson(json);
      } catch (_) {}
    }
    // Eski kayıtlar için fallback
    return Product(
      barcode: row['barcode'] as String,
      productName: row['product_name'] as String? ?? '',
      brand: row['brand'] as String?,
      nutriscoreGrade: row['nutriscore_grade'] as String?,
    );
  }

  // ─── FAVORİLER ───────────────────────────────────────────────
  static Future<void> addFavorite(Product p) async {
    final database = await db;
    await database.insert(
      'favorites',
      {
        'barcode': p.barcode,
        'product_name': p.productName,
        'brand': p.brand,
        'nutriscore_grade': p.nutriscoreGrade,
        'product_json': productToJson(p),
        'date_added': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> removeFavorite(String barcode) async {
    final database = await db;
    await database.delete('favorites', where: 'barcode = ?', whereArgs: [barcode]);
  }

  static Future<bool> isFavorite(String barcode) async {
    final database = await db;
    final res = await database.query('favorites', where: 'barcode = ?', whereArgs: [barcode]);
    return res.isNotEmpty;
  }

  static Future<List<Product>> getFavorites() async {
    final database = await db;
    final res = await database.query('favorites', orderBy: 'date_added DESC');
    return res.map((e) => _fromRow(e)).toList();
  }

  // ─── GEÇMİŞ ─────────────────────────────────────────────────
  static Future<void> addToHistory(Product p) async {
    final database = await db;
    await database.delete('scan_history', where: 'barcode = ?', whereArgs: [p.barcode]);
    await database.insert('scan_history', {
      'barcode': p.barcode,
      'product_name': p.productName,
      'brand': p.brand,
      'nutriscore_grade': p.nutriscoreGrade,
      'product_json': productToJson(p),
      'scan_date': DateTime.now().toIso8601String(),
    });
    // Max 30 kayıt
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM scan_history'),
    )!;
    if (count > 30) {
      await database.rawDelete('''
        DELETE FROM scan_history WHERE id NOT IN (
          SELECT id FROM scan_history ORDER BY scan_date DESC LIMIT 30
        )
      ''');
    }
  }

  static Future<List<Product>> getHistory() async {
    final database = await db;
    final res = await database.query('scan_history', orderBy: 'scan_date DESC');
    return res.map((e) => _fromRow(e)).toList();
  }

  static Future<void> clearHistory() async {
    final database = await db;
    await database.delete('scan_history');
  }

  // Seçili barkodları geçmişten sil (seçmeli temizleme)
  static Future<void> deleteHistoryItems(List<String> barcodes) async {
    if (barcodes.isEmpty) return;
    final database = await db;
    final placeholders = List.filled(barcodes.length, '?').join(',');
    await database.delete(
      'scan_history',
      where: 'barcode IN ($placeholders)',
      whereArgs: barcodes,
    );
  }

  // ─── ÇEVRİMDIŞI CACHE (cached_products) ────────────────────
  // Backend'den gelen ürün tam JSON olarak saklanır;
  // internet yoksa lookup cache'ten döner.
  static Future<void> cacheProduct(Product p) async {
    final database = await db;
    await database.insert(
      'cached_products',
      {
        'barcode': p.barcode,
        'data_json': productToJson(p),
        'cached_date': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Product?> getCachedProduct(String barcode) async {
    final database = await db;
    final res = await database.query(
      'cached_products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (res.isEmpty) return null;
    try {
      final json = jsonDecode(res.first['data_json'] as String) as Map<String, dynamic>;
      return Product.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Cache'i boyut sınırlı tut (en eski 200 dışında sil)
  static Future<void> trimCache() async {
    final database = await db;
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM cached_products'),
    )!;
    if (count > 300) {
      await database.rawDelete('''
        DELETE FROM cached_products WHERE barcode NOT IN (
          SELECT barcode FROM cached_products ORDER BY cached_date DESC LIMIT 200
        )
      ''');
    }
  }

  // ─── AYARLAR ─────────────────────────────────────────────────
  static Future<String?> getSetting(String key) async {
    final database = await db;
    final res = await database.query('user_settings', where: 'key = ?', whereArgs: [key]);
    return res.isNotEmpty ? res.first['value'] as String : null;
  }

  static Future<void> setSetting(String key, String value) async {
    final database = await db;
    await database.insert(
      'user_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
