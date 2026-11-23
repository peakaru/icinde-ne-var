import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../services/database_service.dart';

/// 429 — rate limit: çok hızlı istek gönderildi, ~1 dk beklemek gerek
class RateLimitException implements Exception {
  @override
  String toString() => 'RateLimitException';
}

class ApiService {
  static const String baseUrl = 'https://peakaru-peakaru-backend-v2.hf.space';

  static Future<Product> lookupBarcode(String barcode) async {
    final response = await http
        .get(Uri.parse('$baseUrl/barcode/$barcode'))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return Product.fromJson(data);
    } else if (response.statusCode == 429) {
      throw RateLimitException();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Barkod bulunamadı');
    }
  }
}

/// Lookup sonucu — fromCache=true ise çevrimdışı cache'ten geldi
class LookupResult {
  final Product product;
  final bool fromCache;
  LookupResult({required this.product, required this.fromCache});
}

class LookupService {
  /// Barkod sorgula — online dener, başarılıysa cache'ler;
  /// internet yoksa veya rate limit dolarsa cache'ten döndürür.
  static Future<LookupResult> lookup(String barcode) async {
    try {
      final product = await ApiService.lookupBarcode(barcode);
      // Başarılı — cache'le (fire-and-forget, bekletme)
      DatabaseService.cacheProduct(product).then((_) => DatabaseService.trimCache());
      return LookupResult(product: product, fromCache: false);
    } catch (e) {
      // 404 (ürün yok) ile geçici hataları ayır:
      // ürün yoksa cache'te de yoktur — exception fırlat
      final msg = e.toString();
      final isRateLimit = e is RateLimitException || msg.contains('RateLimitException');
      final isNetworkError = msg.contains('SocketException') ||
          msg.contains('TimeoutException') ||
          msg.contains('timed out') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Connection');

      if (!isRateLimit && !isNetworkError) rethrow;

      // Geçici hata (network / rate limit) — cache dene
      final cached = await DatabaseService.getCachedProduct(barcode);
      if (cached != null) {
        return LookupResult(product: cached, fromCache: true);
      }
      if (isRateLimit) throw RateLimitException();
      rethrow; // cache'te de yoksa hatayı yukselt
    }
  }
}

class SearchResult {
  final String barcode;
  final String productName;
  final String brand;
  final String? nutriscore; // "a".."e" veya null (hesaplanamadı)
  SearchResult({required this.barcode, required this.productName, required this.brand, this.nutriscore});

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        barcode: j['barcode'] ?? '',
        productName: j['product_name'] ?? 'Bilinmeyen Ürün',
        brand: j['brand'] ?? '',
        nutriscore: j['nutriscore'],
      );

  /// Nutri-Score harfine göre renk (ürün detayiyle aynı palet)
  Color get nutriscoreColor {
    switch (nutriscore?.toUpperCase()) {
      case 'A': return const Color(0xFF038141);
      case 'B': return const Color(0xFF85BB2F);
      case 'C': return const Color(0xFFFECB02);
      case 'D': return const Color(0xFFEE8100);
      case 'E': return const Color(0xFFE63E11);
      default: return const Color(0xFF64748B);
    }
  }
}

class SearchService {
  static const String baseUrl = ApiService.baseUrl;

  /// Ürün adına göre ara (min 2 karakter). Barkod bilinmediğinde kullanılır.
  /// 429 (rate limit) geldiğinde boş liste yerine RateLimitException fırlatır
  /// ki arayüz "sonuç yok" ile "çok hızlı istek"i ayırt edebilsin.
  static Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final response = await http
        .get(Uri.parse('$baseUrl/search?q=${Uri.encodeComponent(query)}&limit=$limit'))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final list = data['results'] as List<dynamic>? ?? [];
      return list.map((e) => SearchResult.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 429) {
      throw RateLimitException();
    } else {
      return [];
    }
  }
}
