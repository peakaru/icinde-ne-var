/// Sayıyı dile göre yazar: Türkçede ondalık ayırıcı virgüldür (38,0 g).
String fmtNum(double value, int decimals, String lang) {
  final s = value.toStringAsFixed(decimals);
  return lang == 'tr' ? s.replaceAll('.', ',') : s;
}

/// Listeyi cümle içinde birleştirir: "şeker, tuz ve protein" / "sugars, salt and protein".
String joinWords(List<String> words, String lang) {
  if (words.length <= 1) return words.join();
  final last = words.last;
  return '${words.sublist(0, words.length - 1).join(', ')} ${lang == 'tr' ? 've' : 'and'} $last';
}

/// Aramada büyük/küçük harf ve Türkçe karakter farkını yok sayar:
/// "ÇİKOLATA", "çikolata" ve "cikolata" aynı sonucu verir.
String foldForSearch(String s) {
  const map = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
  final lower = s.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(map[ch] ?? ch);
  }
  return out.toString();
}
