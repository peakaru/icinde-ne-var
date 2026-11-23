"""
Pure product-analysis logic for the İçinde Ne Var? backend.

No web framework or database imports, so everything here can be unit-tested
in isolation: Nutri-Score (2023 algorithm), beverage detection, sodium unit
normalisation, fruit/vegetable/legume estimate, allergen detection,
additive risk matching and the search-term normaliser.
"""
import re
from dataclasses import dataclass
from typing import Dict, List, Tuple


def fold_i(text: str) -> str:
    """Lowercase text for keyword matching across Turkish and English.

    Python's str.lower() turns "I" into "i" and "İ" into "i" + U+0307, so an
    uppercase Turkish label such as "FINDIK" or "PEYNİR" never matched the
    lowercase keywords "fındık" / "peynir". Folding I, İ, ı and i to a plain
    "i" (on both the text and the keywords) fixes that while English words
    ("MILK" -> "milk") keep matching.
    """
    return (text or "").replace("İ", "i").lower().replace("̇", "").replace("ı", "i")


# Alerjenler (EU 1169/2011 — 14 büyük alerjen)
ALLERGENS = {
    "süt": ["süt", "laktoz", "peynir", "milk", "lait", "cream", "whey",
            "butter", "lactose", "yoğurt", "kefir", "krema"],
    "gluten": ["buğday", "gluten", "wheat", "flour", "barley", "rye",
               "arpa", "çavdar", "yulaf (glutenli)"],
    "yumurta": ["yumurta", "egg", "albumin", "yumurta akı", "yumurta sarısı"],
    "soya": ["soya", "soy", "soya lesitini"],
    "kuruyemiş": ["fıstık", "fındık", "ceviz", "badem", "antep fıstığı",
                  "hindistan cevizi", "peanut", "hazelnut", "walnut",
                  "almond", "pistachio", "cashew", "kaju"],
    "balık": ["balık", "fish", "seafood", "ton balığı", "somon"],
    "susam": ["susam", "sesame", "tahini", "tahin"],
    "hardal": ["hardal", "mustard"],
    "kereviz": ["kereviz", "celery"],
    "sülfit": ["sülfit", "sulfit", "kükürt dioksit", "sulfite"],
}


@dataclass
class ProductFeatures:
    energy_100g: float = 0       # kcal/100g
    sugars_100g: float = 0       # g/100g
    saturated_fat_100g: float = 0  # g/100g
    sodium_100g: float = 0       # mg/100g (normalize edilmiş)
    proteins_100g: float = 0     # g/100g
    fiber_100g: float = 0        # g/100g


# ============================================================
# BİRİM NORMALİZASYONU (BUG 1 düzeltmesi)
# ============================================================
_FVLN_KELIME = (r"(?:meyve|fruit|sebze|vegetable|domates|tomato|elma|apple|armut|pear|"
    r"cilek|strawberry|muz|banana|portakal|orange|mandalina|havuc|carrot|ispanak|"
    r"spinach|biber|pepper|patlican|kabak|zucchini|uzum|grape|kiraz|cherry|kayisi|"
    r"apricot|seftali|peach|incir|fig|nar|pomegranate|ananas|pineapple|mango|bakla|"
    r"mercimek|lentil|fasulye|bean|nohut|chickpea|bezelye|pea|barbunya)")
_FVLN_RE = re.compile(_FVLN_KELIME + r"[^,;()]{0,25}?\s*%\s*(\d{1,3})(?:[.,]\d+)?", re.I)


def fvln_tahmin(text) -> float:
    """Icindekilerden meyve/sebze/baklagil toplam orani tahmini (0-100).
    'Elma %35, Uzum %20' -> 55"""
    if not text:
        return 0.0
    toplam = 0.0
    for m in _FVLN_RE.finditer(text):
        try:
            toplam += float(m.group(1))
        except ValueError:
            pass
    return min(toplam, 100.0)


def normalize_sodium_mg(val) -> float:
    """
    Sodium değerini mg'a normalize et.
    OFF ve DB'deki sodium_100g değeri karışık birimde olabilir:
      - 0.304 → 0.304g = 304mg (gram)
      - 492   → 492mg (zaten mg)
      - 0.00018 → 0.18mg (gram, çok küçük)

    Eşik: 90 mg (Nutri-Score'un ilk puan eşiği). 90'dan büyükse zaten mg.
    """
    if val is None:
        return 0.0
    try:
        v = float(val)
    except (TypeError, ValueError):
        return 0.0
    if v <= 0:
        return 0.0
    # Sağduyu eşiği: gıda ürünlerinde 100g başına sodium nadiren 3000mg'ı geçer
    # (>3g tuz değil sodium). 90'dan küçükse gram geldi kabul edip *1000.
    if v < 90:
        return v * 1000.0
    return v


# ============================================================
# İÇECEK KATEGORİSİ TESPİTİ (BUG 4 düzeltmesi)
# ============================================================
BEVERAGE_KEYWORDS = [
    # Türkçe (uzun ifadeler — substring match güvenli)
    "maden suyu", "ayran", "gazoz", "limonata", "içecek",
    "meyve suyu", "şeftali suyu", "portakal suyu", "elma suyu", "vişne suyu",
    "kahve", "türk kahvesi", "filtre kahve", "süt içeceği",
    "muzlu süt", "çikolatalı süt", "smoothie", "kefir", "kombucha",
    "enerji içeceği", "ice tea", "buzlu çay", "şekerli içecek",
    # İngilizce (uzun — güvenli)
    "juice", "drink", "water", "coffee", "beverage",
    "lemonade", "milkshake",
]

# Kısa keyword'ler için KELİME SINIRI zorunlu (false-positive önlemek)
BEVERAGE_KEYWORDS_WORD_BOUNDARY = [
    "kola", "soda", "çay", "su", "tea", "cola", "milk",
]


def is_beverage(product_name: str) -> bool:
    """Ürün adından içecek olup olmadığını tespit et."""
    name_lower = fold_i(product_name)
    # Uzun keyword'ler: substring yeterince güvenli
    for kw in BEVERAGE_KEYWORDS:
        if fold_i(kw) in name_lower:
            return True
    # Kısa keyword'ler: kelime sınırı şart (ChocoLait içinde 'cola' var!)
    for kw in BEVERAGE_KEYWORDS_WORD_BOUNDARY:
        pattern = r'\b' + re.escape(fold_i(kw)) + r'\b'
        if re.search(pattern, name_lower):
            return True
    return False


# ============================================================
# RESMI NUTRI-SCORE 2022/2023 ALGORİTMASI (BUG 5, 6 düzeltmesi)
# Kaynak: AESAN 2022 + BMEL 2023 beverage update
# ============================================================
def _points_energy(energy_kj: float, beverage: bool) -> int:
    if beverage:
        return min(10, int(energy_kj // 90)) if energy_kj > 0 else 0
    # Katı gıda eşik tablosu
    thresholds = [335, 670, 1005, 1340, 1675, 2010, 2345, 2680, 3015, 3350]
    for i, t in enumerate(thresholds):
        if energy_kj <= t:
            return i
    return 10


def _points_sugars(sugars_g: float, beverage: bool) -> int:
    if beverage:
        # Non-linear (0.5, 2.0, 3.5, 4.5, ...)
        thresholds = [0.5, 2.0, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5]
    else:
        thresholds = [4.5, 9.0, 13.5, 18.0, 22.5, 27.0, 31.0, 36.0, 40.0, 45.0]
    for i, t in enumerate(thresholds):
        if sugars_g <= t:
            return i
    return 10


def _points_saturated_fat(sat_fat_g: float) -> int:
    thresholds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    for i, t in enumerate(thresholds):
        if sat_fat_g <= t:
            return i
    return 10


def _points_sodium(sodium_mg: float) -> int:
    thresholds = [90, 180, 270, 360, 450, 540, 630, 720, 810, 900]
    for i, t in enumerate(thresholds):
        if sodium_mg <= t:
            return i
    return 10


def _points_fiber(fiber_g: float) -> int:
    thresholds = [0.9, 1.9, 2.8, 3.7, 4.7]
    for i, t in enumerate(thresholds):
        if fiber_g <= t:
            return i
    return 5


def _points_proteins(proteins_g: float) -> int:
    thresholds = [1.6, 3.2, 4.8, 6.4, 8.0]
    for i, t in enumerate(thresholds):
        if proteins_g <= t:
            return i
    return 5


def calculate_nutri_score_2024(f: ProductFeatures, fvln_pct: float = 0,
                                product_name: str = "") -> Tuple[str, int, dict]:
    """
    Resmi Nutri-Score 2022/2023 algoritması.

    Returns: (grade, total_points, breakdown)
    """
    beverage = is_beverage(product_name)

    # kcal → kJ (1 kcal = 4.184 kJ)
    energy_kj = f.energy_100g * 4.184

    # Negatif puanlar
    pts_energy = _points_energy(energy_kj, beverage)
    pts_sugars = _points_sugars(f.sugars_100g, beverage)
    pts_satfat = _points_saturated_fat(f.saturated_fat_100g)
    pts_sodium = _points_sodium(f.sodium_100g)
    negative_total = pts_energy + pts_sugars + pts_satfat + pts_sodium

    # Pozitif puanlar
    pts_fiber = _points_fiber(f.fiber_100g)
    pts_proteins = _points_proteins(f.proteins_100g)

    # KRİTİK KURAL (BUG 6 düzeltmesi):
    # Negatif ≥11 ve meyve/sebze tam puan değilse protein sayılmaz.
    # FVLN verisi olmadığı için 0 kabul ediyoruz (konservatif).
    # FVLN: icindekilerden tahmin edilen meyve/sebze/baklagil orani (bandlar: 40/60/80)
    fvln_pts = 0
    if fvln_pct >= 80:
        fvln_pts = 5
    elif fvln_pct >= 60:
        fvln_pts = 2
    elif fvln_pct >= 40:
        fvln_pts = 1
    if negative_total >= 11 and fvln_pts < 5:
        proteins_effective = 0
        protein_rule_applied = True
    else:
        proteins_effective = pts_proteins
        protein_rule_applied = False

    positive_total = fvln_pts + pts_fiber + proteins_effective
    total_points = negative_total - positive_total

    # Grade eşleştirme
    if beverage:
        if total_points <= 0 and negative_total == 0:
            grade = "A"
        elif total_points <= 1:
            grade = "B"
        elif total_points <= 5:
            grade = "C"
        elif total_points <= 9:
            grade = "D"
        else:
            grade = "E"
    else:
        if total_points <= -1:
            grade = "A"
        elif total_points <= 2:
            grade = "B"
        elif total_points <= 10:
            grade = "C"
        elif total_points <= 18:
            grade = "D"
        else:
            grade = "E"

    breakdown = {
        "energy": {"value": f.energy_100g, "unit": "kcal", "points": pts_energy},
        "sugars": {"value": f.sugars_100g, "unit": "g", "points": pts_sugars},
        "saturated_fat": {"value": f.saturated_fat_100g, "unit": "g", "points": pts_satfat},
        "sodium": {"value": f.sodium_100g, "unit": "mg", "points": pts_sodium},
        "proteins": {"value": f.proteins_100g, "unit": "g", "points": -proteins_effective},
        "fiber": {"value": f.fiber_100g, "unit": "g", "points": -pts_fiber},
    }

    return grade, total_points, breakdown


# ============================================================
# ALERJEN TESPİTİ (SORUN 7 düzeltmesi — false-positive azaltma)
# ============================================================
# Kısa keyword'lerden sonra izin verilen ekler: "inek sütü", "sütlü", "sütten",
# "yumurtalı", "eggs". Yokluk eki (-siz/-suz: "sütsüz") listede yok, eşleşmez;
# "eggplant" / "arpacık" gibi başka kelimeler de eşleşmez.
_ALLERGEN_SUFFIX = r"(?:s|[iuü]|l[iuü]|y[ae]|[ae]|[dt][ae]n?|l[ae]r|s[iuü]|n[iuü]n)?"

# Keyword'den hemen sonra gelirse alerjenin YOKLUĞUNU anlatan ifadeler:
# "glutensiz", "gluten içermez", "gluten-free", "glutenfrei"
_NEGATION_AFTER = re.compile(r"\s*-?\s*(?:s[iuü]z|free\b|frei\b|i[cç]ermez)")

# Alerjen keyword'ü içeren ama alerjen olmayan kalıplar
_NON_ALLERGEN_PHRASES = tuple((fold_i(a), fold_i(b)) for a, b in (
    ("cocoa butter", "cocoa"),
    ("cacao butter", "cacao"),
    ("shea butter", "shea"),
    ("coconut milk", "coconut"),
    ("hindistan cevizi sütü", "hindistan cevizi"),
    ("cream of tartar", "tartar"),
    ("balık kraker", "kraker"),  # balık şeklinde kraker, balık içermez
))


def detect_allergens(text: str) -> List[str]:
    """İçerik metninden alerjen tespit et (false-positive azaltılmış).

    Büyük harfli Türkçe etiketleri ("FINDIK", "PEYNİR") ve Türkçe ekleri
    ("inek sütü") tanır; "glutensiz" ve "cocoa butter" alerjen sayılmaz.
    """
    text_f = fold_i(text)
    for phrase, replacement in _NON_ALLERGEN_PHRASES:
        text_f = text_f.replace(phrase, replacement)
    found = []
    for allergen, keywords in ALLERGENS.items():
        for kw in keywords:
            kw_f = fold_i(kw)
            # Kısa keyword'ler için kelime sınırı zorunlu (izin verilen eklerle)
            if len(kw_f) <= 4:
                pattern = r'\b' + re.escape(kw_f) + _ALLERGEN_SUFFIX + r'\b'
            else:
                pattern = re.escape(kw_f)
            if any(not _NEGATION_AFTER.match(text_f, m.end())
                   for m in re.finditer(pattern, text_f)):
                found.append(allergen)
                break
    return found


# ============================================================
# RİSK ANALİZİ (BUG 2 düzeltmesi — v3.0.0 şema)
# ============================================================
def analyze_ingredients(text: str, risk_scores: Dict[str, dict]) -> Tuple[List[Dict], int]:
    """
    İçerik metninden riskli katkı maddelerini tespit et.
    v3.0.0 şema: name, ewg_score, risk, evidence, color, source_detail
    """
    found_risks = []
    max_ewg = 0

    # İçerikleri split et
    ingredients = [x.strip() for x in re.split(r'[,.]', text) if len(x.strip()) > 1]

    for ingredient in ingredients:
        ingredient_lower = fold_i(ingredient)
        for key, info in risk_scores.items():
            if not isinstance(info, dict):
                continue
            keywords = info.get("keywords", []) + [key]
            matched = False
            for kw in keywords:
                kw_lower = fold_i(kw)
                if len(kw_lower) <= 3:
                    # Çok kısa keyword — kelime sınırı şart
                    pattern = r'\b' + re.escape(kw_lower) + r'\b'
                    if re.search(pattern, ingredient_lower):
                        matched = True
                        break
                elif len(kw_lower) <= 5:
                    pattern = r'\b' + re.escape(kw_lower) + r'\b'
                    if re.search(pattern, ingredient_lower):
                        matched = True
                        break
                else:
                    if kw_lower in ingredient_lower:
                        matched = True
                        break

            if matched:
                ewg = info.get("ewg_score", 1)
                found_risks.append({
                    # Geriye uyumlu alanlar (Flutter'a dokunmaz)
                    "name": info.get("name", key),
                    "name_en": info.get("name_en", ""),  # İngilizce UI için
                    "ewg_score": ewg,
                    "risk": info.get("risk", ""),
                    "risk_en": info.get("risk_en", ""),  # İngilizce UI açıklaması
                    # Yeni alanlar (v3.0.0 — kanıt-etiketli model)
                    "evidence": info.get("evidence", "limited"),
                    "color": info.get("color", "yellow"),
                    "source": info.get("source_detail", ""),
                    "source_en": info.get("source_en", ""),  # İngilizce kaynak metni
                })
                max_ewg = max(max_ewg, ewg)
                break  # Aynı madde için tek eşleşme yeterli

    # Dedupe (isim bazlı)
    seen = set()
    unique_risks = []
    for r in found_risks:
        if r["name"] not in seen:
            seen.add(r["name"])
            unique_risks.append(r)

    return unique_risks, max_ewg


def _tr_norm(s: str) -> str:
    """Tam Türkçe normalize: ığüşöç → igusoc (arama terimi için).

    fold_i önce gelir: "İçim".lower() → "i̇çim" (birleşik nokta) olduğu için
    büyük İ ile yazılan aramalar veritabanındaki "icim" ile hiç eşleşmiyordu.
    """
    s = fold_i(s)
    table = str.maketrans("ğüşöçî", "gusoci")
    return s.translate(table)
