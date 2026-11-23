import 'package:flutter/material.dart';

/// Yasal ekran — Gizlilik Politikası, Kullanım Şartları, Sorumluluk Reddi, İletişim.
/// TR/EN çift dil (isTr). Play Store öncesi uyumluluk paketinin uygulama içi ayağı.
class LegalScreen extends StatelessWidget {
  final bool isTr;
  const LegalScreen({super.key, required this.isTr});

  @override
  Widget build(BuildContext context) {
    final List<({String title, List<String> paras})> sections = isTr ? _trSections : _enSections;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1512),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1512),
        title: Text(isTr ? 'Yasal Bilgiler' : 'Legal',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        itemBuilder: (context, i) {
          final s = sections[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF132720),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title,
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 15,
                        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 10),
                ...s.paras.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(p,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.55)),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<({String title, List<String> paras})> get _trSections => [
      (
        title: 'GİZLİLİK POLİTİKASI',
        paras: [
          'Son güncelleme: Eylül 2026',
          'Bu politika, "İçinde Ne Var?" uygulaması ("Uygulama") tarafından işlenen kişisel verilerin hangi amaçlarla, ne şekilde işlendiğini 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) ve Avrupa Birliği Genel Veri Koruma Tüzüğü (GDPR) uyarınca açıklar.',
          '1. İşlenen veriler: Uygulama yalnızca aşağıdaki asgari verileri işler: (a) tarattığınız ürün barkod numaraları, (b) arama kutusuna girdiğiniz ürün adları, (c) görsel analiz özelliğini kullanırsanız, yüklediğiniz ürün fotoğrafları. Konum, rehber, bildirim kimliği, reklam kimliği veya cihaz tanımlayıcıları TOPLANMAZ.',
          '2. Verilerin işlenme amacı: Taranan barkodların ve aramaların ürün veritabanında eşleştirilmesi ve sonuçların gösterilmesi. Fotoğraflar yalnızca barkod/etiket okuma amacıyla işlenir; kalıcı olarak saklanmaz.',
          '3. Üçüncü taraflara aktarım: Ürün sorguları, barındırma altyapısı olarak Hugging Face (ABD/AB) ve açık kaynaklı Open Food Facts veritabanına iletilir. Bu aktarımlar yalnızca tarama sonucu üretmek içindir; pazarlama veya profil oluşturma amacıyla veri satılmaz veya paylaşılmaz.',
          '4. Yerel depolama: Arama geçmişiniz, favorileriniz ve alerjen tercihleriniz yalnızca kendi cihazınızda saklanır; sunucularımıza gönderilmez.',
          '5. Analitik ve izleme: Uygulama içinde hiçbir analitik, reklam veya izleme bileşeni (Firebase Analytics, çerez, piksel vb.) KULLANILMAZ.',
          '6. Saklama: Sorgular sunucu tarafında yalnızca standart sistem günlüklerinde geçici olarak yer alır; ayrı bir kullanıcı profili oluşturulmaz.',
          '7. KVKK/GDPR haklarınız: Verilerinizin işlenmesine ilişkin bilgi alma, düzeltme, silme ve işlemeye itiraz etme haklarınız için iletişim bölümündeki adresten başvurabilirsiniz.',
        ],
      ),
      (
        title: 'KULLANIM ŞARTLARI',
        paras: [
          '1. Uygulama, ürünlerin içerik ve besin bilgilerini kamuya açık kaynaklardan derleyerek sunar. Bilgilerin eksiksiz, güncel veya hatasız olduğunu taahhüt etmiyoruz; ürün ambalajındaki resmî etiket bilgileri esas alınmalıdır.',
          '2. Uygulama ücretsizdir; abonelik, iç satın alma veya reklam içermez.',
          '3. Uygulamanın kaynak kodları ve görsel öğeleri telif hakkı korumasındadır. Ürün fotoğrafları ilgili markaların/Marketlerin CDN sunucularından doğrudan gösterilir; bu markaların mülkiyetindedir.',
          '4. Uygulamanın kötüye kullanımı, otomatik veri çekme (scraping) aracı olarak kullanılması veya hizmete kasıtlı aşırı yük bindirilmesi yasaktır.',
          '5. Şartlarda yapılacak değişiklikler uygulama içinde yayımlanır; değişiklik sonrası uygulamayı kullanmaya devam etmek kabul sayılır.',
        ],
      ),
      (
        title: 'SORUMLULUK REDDİ (FERAGATNAME)',
        paras: [
          'Bu uygulamadaki Nutri-Score puanları, içerik analizleri ve "risk" bilgileri yalnızca GENEL BİLGİLENDİRME amaçlıdır; tıbbi teşhis, tedavi veya diyet tavsiyesi DEĞİLDİR.',
          'Alerjen ve intolerans bilgileri ürün etiketlerinden derlenmiştir; alerjiniz varsa ürünü tüketmeden önce mutlaka ambalaj üzerindeki resmî alerjen bildirimini okuyun ve gerektiğinde hekiminize veya eczacınıza danışın.',
          'Nutri-Score, bilimsel değerlendirme tartışmaları süren bir ön etiketleme sistemidir; tek başına bir ürünün "sağlıklı" veya "sağlıksız" olduğunun kanıtı olarak yorumlanmamalıdır.',
        ],
      ),
      (
        title: 'İLETİŞİM, İADE VE ÇEREZ',
        paras: [
          'İletişim: Geliştiriciye Play Store geliştirici sayfasındaki e-posta adresinden ulaşabilirsiniz; KVKK başvuruları da aynı adrese yapılır.',
          'İade: Uygulama ücretsizdir ve iç satın alma içermediğinden iade süreci bulunmamaktadır.',
          'Çerez: Uygulama çerez veya benzeri izleme teknolojisi KULLANMAZ; bu nedenle çerez onayı akışı gerekmemektedir.',
          'Erişilebilirlik: Uygulama, ekran okuyucu etiketleri, yeterli renk kontrastı ve büyük dokunma alanlarıyla erişilebilirlik standartlarına uygun geliştirilmiştir. Erişilebilirlik sorunlarını bildirmek için iletişim adresini kullanabilirsiniz.',
        ],
      ),
    ];

List<({String title, List<String> paras})> get _enSections => [
      (
        title: 'PRIVACY POLICY',
        paras: [
          'Last updated: September 2026',
          'This policy explains how the app "İçinde Ne Var?" ("App") processes personal data, in accordance with the EU General Data Protection Regulation (GDPR) and applicable data protection law.',
          '1. Data processed: The App only processes the following minimal data: (a) product barcode numbers you scan, (b) product names you type into search, (c) product photos you upload if you use the image analysis feature. Location, contacts, notification IDs, advertising IDs or device identifiers are NOT collected.',
          '2. Purpose: Matching scanned barcodes and searches against the product database and displaying results. Photos are processed solely for barcode/label reading and are not retained.',
          '3. Third parties: Product queries are sent to our hosting provider Hugging Face (US/EU) and the open Open Food Facts database, solely to produce scan results. No data is sold or shared for marketing or profiling.',
          '4. Local storage: Your search history, favorites and allergen preferences are stored only on your device and never uploaded.',
          '5. Analytics & tracking: The App contains NO analytics, advertising or tracking components (no Firebase Analytics, cookies or pixels).',
          '6. Retention: Queries appear only transiently in standard server logs; no user profiles are created.',
          '7. Your rights: To exercise your rights of access, rectification, erasure and objection, contact us via the address in the Contact section.',
        ],
      ),
      (
        title: 'TERMS OF USE',
        paras: [
          '1. The App compiles product ingredient and nutrition information from publicly available sources. We do not warrant the information to be complete, current or error-free; the official label on the product packaging is authoritative.',
          '2. The App is free; it contains no subscriptions, in-app purchases or ads.',
          '3. Source code and visual design are copyrighted. Product photos are displayed directly from the respective brands\'/markets\' CDN servers and remain their property.',
          '4. Misuse of the App, including use as an automated data scraping tool or deliberate overload of the service, is prohibited.',
          '5. Changes to these terms will be published in the App; continued use after changes constitutes acceptance.',
        ],
      ),
      (
        title: 'DISCLAIMER',
        paras: [
          'Nutri-Score grades, ingredient analyses and "risk" information in this App are for GENERAL INFORMATION only and are NOT medical diagnosis, treatment or dietary advice.',
          'Allergen and intolerance information is compiled from product labels; if you have allergies, always read the official allergen statement on the packaging before consuming and consult a physician or pharmacist when needed.',
          'Nutri-Score is a front-of-pack labeling system under ongoing scientific debate; it must not be interpreted as sole proof that a product is "healthy" or "unhealthy".',
        ],
      ),
      (
        title: 'CONTACT, REFUNDS AND COOKIES',
        paras: [
          'Contact: You can reach the developer via the e-mail address on the Play Store developer page; GDPR/KVKK requests are handled at the same address.',
          'Refunds: The App is free and contains no in-app purchases, therefore no refund process applies.',
          'Cookies: The App does NOT use cookies or similar tracking technologies; no cookie consent flow is required.',
          'Accessibility: The App is built with screen-reader labels, sufficient color contrast and large touch targets. To report accessibility issues, use the contact address.',
        ],
      ),
    ];
