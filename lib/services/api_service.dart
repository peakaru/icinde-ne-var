import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../services/database_service.dart';

/// 429 — rate limit: çok hızlı istek gönderildi, ~1 dk beklemek gerek
class RateLimitException implements Exception {
  @override
  String toString() => 'RateLimitException';
}

/// 404 — ürün ne veritabanında ne de Open Food Facts'te var
class ProductNotFoundException implements Exception {
  @override
  String toString() => 'ProductNotFoundException';
}

/// Barkod formatı geçersiz (backend 8–14 haneli rakam bekler)
class InvalidBarcodeException implements Exception {
  @override
  String toString() => 'InvalidBarcodeException';
}

/// Sunucuya ulaşılamadı: internet yok, DNS hatası veya zaman aşımı
class NetworkException implements Exception {
  @override
  String toString() => 'NetworkException';
}

/// Sunucu hatası (5xx) ya da çözümlenemeyen yanıt
class ServerException implements Exception {
  final int statusCode;
  ServerException(this.statusCode);
  @override
  String toString() => 'ServerException($statusCode)';
}

class ApiService {
  static const String baseUrl = 'https://peakaru-peakaru-backend-v2.hf.space';

  /// HTTP istemcisi — testlerde `MockClient` ile değiştirilir.
  @visibleForTesting
  static http.Client client = http.Client();

  /// Backend'in kabul ettiği barkod formatı (EAN-8 … GTIN-14)
  static bool isValidBarcode(String code) => RegExp(r'^\d{8,14}$').hasMatch(code);

  /// GET isteği; bağlantı hatalarını [NetworkException]'a çevirir.
  static Future<http.Response> _get(Uri uri, Duration timeout) async {
    try {
      return await client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw NetworkException();
    } on SocketException {
      throw NetworkException();
    } on http.ClientException {
      throw NetworkException();
    }
  }

  static Future<Product> lookupBarcode(String barcode) async {
    if (!isValidBarcode(barcode)) throw InvalidBarcodeException();
    final response = await _get(Uri.parse('$baseUrl/barcode/$barcode'), const Duration(seconds: 30));

    switch (response.statusCode) {
      case 200:
        try {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          return Product.fromJson(data);
        } on FormatException {
          throw ServerException(response.statusCode);
        } on TypeError {
          throw ServerException(response.statusCode);
        }
      case 400:
        throw InvalidBarcodeException();
      case 404:
        throw ProductNotFoundException();
      case 429:
        throw RateLimitException();
      default:
        throw ServerException(response.statusCode);
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
  /// Barkod sorgula — online dener, başarılıysa cache'ler; internet yoksa,
  /// sunucu yanıt vermiyorsa veya rate limit dolduysa cache'ten döndürür.
  /// Ürün gerçekten yoksa ([ProductNotFoundException]) ya da barkod geçersizse
  /// cache'e bakılmaz — hata olduğu gibi yukarı çıkar.
  static Future<LookupResult> lookup(String barcode) async {
    try {
      final product = await ApiService.lookupBarcode(barcode);
      // Başarılı — cache'le (fire-and-forget; cache hatası sorguyu bozmasın)
      DatabaseService.cacheProduct(product)
          .then((_) => DatabaseService.trimCache())
          .catchError((Object e) => debugPrint('Cache yazılamadı: $e'));
      return LookupResult(product: product, fromCache: false);
    } on NetworkException {
      return _fromCacheOr(barcode, NetworkException());
    } on RateLimitException {
      return _fromCacheOr(barcode, RateLimitException());
    } on ServerException catch (e) {
      return _fromCacheOr(barcode, e);
    }
  }

  static Future<LookupResult> _fromCacheOr(String barcode, Exception error) async {
    final cached = await DatabaseService.getCachedProduct(barcode);
    if (cached != null) return LookupResult(product: cached, fromCache: true);
    throw error;
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
      case 'A':
        return const Color(0xFF038141);
      case 'B':
        return const Color(0xFF85BB2F);
      case 'C':
        return const Color(0xFFFECB02);
      case 'D':
        return const Color(0xFFEE8100);
      case 'E':
        return const Color(0xFFE63E11);
      default:
        return const Color(0xFF64748B);
    }
  }
}

class SearchService {
  /// Ürün adına göre ara (min 2 karakter). Barkod bilinmediğinde kullanılır.
  /// 429'da [RateLimitException], bağlantı yoksa [NetworkException], sunucu
  /// hatasında [ServerException] fırlatır; böylece arayüz "sonuç yok" ile
  /// "arama yapılamadı"yı ayırt edebilir.
  static Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final response = await ApiService._get(
      Uri.parse('${ApiService.baseUrl}/search?q=${Uri.encodeComponent(query)}&limit=$limit'),
      const Duration(seconds: 15),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final list = data['results'] as List<dynamic>? ?? [];
      return list.map((e) => SearchResult.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 429) {
      throw RateLimitException();
    } else if (response.statusCode == 400) {
      return [];
    } else {
      throw ServerException(response.statusCode);
    }
  }
}
