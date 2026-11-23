import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icinde_ne_var/services/api_service.dart';

/// Her isteğe [handler]'ın yanıtını döndüren sahte istemci kurar.
void useResponse(http.Response Function(http.Request) handler) {
  ApiService.client = MockClient((req) async => handler(req));
}

http.Response jsonResponse(Object body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  const barcode = '8690504040248';

  test('200 yanıtı Product olarak döner', () async {
    useResponse((_) => jsonResponse({
          'barcode': barcode,
          'product_name': 'Fındıklı Gofret',
          'nutri_score': {'grade': 'd', 'points': 15},
        }, 200));
    final p = await ApiService.lookupBarcode(barcode);
    expect(p.productName, 'Fındıklı Gofret');
    expect(p.nutriscoreGrade, 'd');
  });

  test('404 ProductNotFoundException fırlatır', () async {
    useResponse((_) => jsonResponse({'detail': 'Ürün bulunamadı'}, 404));
    expect(ApiService.lookupBarcode(barcode), throwsA(isA<ProductNotFoundException>()));
  });

  test('429 RateLimitException fırlatır', () async {
    useResponse((_) => jsonResponse({'detail': 'Çok fazla istek'}, 429));
    expect(ApiService.lookupBarcode(barcode), throwsA(isA<RateLimitException>()));
  });

  test('JSON olmayan 500 yanıtı ServerException olur (FormatException değil)', () async {
    useResponse((_) => http.Response('Internal Server Error', 500));
    expect(ApiService.lookupBarcode(barcode), throwsA(isA<ServerException>()));
  });

  test('bağlantı hatası NetworkException olur', () async {
    ApiService.client = MockClient((_) async => throw http.ClientException('Failed host lookup'));
    expect(ApiService.lookupBarcode(barcode), throwsA(isA<NetworkException>()));
  });

  test('geçersiz barkod istek atmadan InvalidBarcodeException fırlatır', () async {
    var calls = 0;
    ApiService.client = MockClient((_) async {
      calls++;
      return http.Response('', 200);
    });
    for (final code in ['123456', '12345678901234567', 'ABC12345']) {
      await expectLater(ApiService.lookupBarcode(code), throwsA(isA<InvalidBarcodeException>()));
    }
    expect(calls, 0);
  });

  test('isValidBarcode EAN-8 … GTIN-14 kabul eder', () {
    expect(ApiService.isValidBarcode('12345678'), isTrue);
    expect(ApiService.isValidBarcode('8690504040248'), isTrue);
    expect(ApiService.isValidBarcode('1234567'), isFalse);
  });

  test('aramadan gelen yerel kimlik (LOC + 12 hex) kabul edilir', () {
    expect(ApiService.isValidBarcode('LOC033758d59457'), isTrue);
    expect(ApiService.isLocalId('LOC033758d59457'), isTrue);
    expect(ApiService.isValidBarcode('LOC123'), isFalse);
    expect(ApiService.isLocalId('8690504040248'), isFalse);
  });

  test('arama sunucu hatasında ServerException fırlatır (boş liste değil)', () async {
    useResponse((_) => http.Response('Internal Server Error', 500));
    expect(SearchService.search('nutella'), throwsA(isA<ServerException>()));
  });
}
