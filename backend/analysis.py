"""
Pure product-analysis logic for the İçinde Ne Var? backend.

No web framework or database imports, so everything here can be unit-tested
in isolation: Nutri-Score (2023 algorithm), beverage detection, sodium unit
normalisation, fruit/vegetable/legume estimate, allergen detection,
additive risk matching and the search-term normaliser.
"""
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


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
# Veri setinde Türkçe dışında çok sayıda Fransızca/Almanca/İspanyolca/İtalyanca
# etiket var; yaygın karşılıklar da listede. 4 karakter ve altı keyword'ler
# kelime sınırıyla, uzunlar alt-dizgi olarak aranır (bkz. detect_allergens).
ALLERGENS = {
    "süt": ["süt", "süttoz", "laktoz", "peynir", "kaşar", "tereyağ", "kaymak", "krema",
            "yoğurt", "ayran", "kefir", "labne", "kazein",
            "milk", "cream", "whey", "butter", "cheese", "lactose", "casein",
            "yoghurt", "ghee",
            "lait", "laiti", "lactos", "fromage", "beurre", "yaourt",
            "milch", "molke", "käse", "jogurt", "joghurt",
            "leche", "queso", "latte", "lattosio", "formaggio", "melk", "kaas",
            "mleko", "mleczn", "maito", "mjölk"],
    # AB 1169/2011 ve TGK: buğday, çavdar, arpa, yulaf, kavılca, kamut
    "gluten": ["buğday", "gluten", "çavdar", "arpa", "yulaf", "bulgur", "irmik",
               "irmiğ", "galeta", "kuskus",
               "wheat", "flour", "barley", "rye", "oat", "semolina", "malt",
               "couscous", "seitan", "kamut", "khorasan",
               "blé", "épeautre", "orge", "seigle", "avoine",
               "weizen", "dinkel", "gerste", "roggen", "hafer",
               "trigo", "avena", "frumento", "spelt", "tarwe", "gerst", "rogge",
               "haver", "pszen"],
    "yumurta": ["yumurta", "egg", "albumen", "ovalbumin", "ovoalbumin",
                "oeuf", "œuf", "eier", "eigelb", "eiklar", "vollei", "hühnerei",
                "eipulver", "huevo", "uovo", "uova", "eieren", "eigeel",
                "jaja", "jaj", "jajeczn"],
    "soya": ["soya", "soy", "soja", "soia", "edamame", "tofu"],
    # Yer fıstığı + sert kabuklu meyveler (hindistan cevizi AB listesinde yok)
    "kuruyemiş": ["fıstık", "fıstığ", "fındık", "fındığ", "ceviz", "badem", "kaju",
                  "pekan", "makadamya", "sert kabuklu",
                  "peanut", "hazelnut", "walnut", "almond", "pistachio", "cashew",
                  "pecan", "macadamia", "brazil nut", "nut",
                  "noisette", "amande", "noix", "cajou", "pistache", "arachid",
                  "fruits a coque", "haselnuss", "mandel", "walnuss", "erdnuss",
                  "schalenfrucht", "avellana", "almendra", "cacahuet",
                  "frutos de cascara", "frutos secos", "nocciol", "mandorl",
                  "pistacchi", "frutta a guscio", "hazelno", "walnoot", "pinda",
                  "orzech", "migdał"],
    "balık": ["balık", "balığ", "hamsi", "uskumru", "levrek", "çipura", "sardalya", "morina",
              "somon", "fish", "seafood", "salmon", "tuna", "cod", "anchov",
              "sardine", "mackerel", "herring",
              "poisson", "saumon", "thon", "anchois", "fisch", "makrele", "hering",
              "pescado", "atún", "pesce", "tonno", "haring"],
    "kabuklu": ["karides", "yengeç", "ıstakoz", "kerevit", "kabuklu deniz",
                "kabuklular",
                "shrimp", "prawn", "crab", "lobster", "langoustine", "crayfish",
                "crustace", "crevette", "garnele", "krabbe", "hummer", "krebs",
                "gamba", "langosta", "gambero"],
    "yumuşakça": ["midye", "kalamar", "ahtapot", "istiridye", "salyangoz", "sepya",
                  "yumuşakça", "mussel", "squid", "octopus", "oyster", "clam",
                  "scallop", "snail", "escargot", "mollus", "moules", "calamar",
                  "poulpe", "huître", "seiche", "muscheln", "vongole", "cozze"],
    "susam": ["susam", "tahin", "sesame", "sésame", "sesam"],
    "hardal": ["hardal", "mustard", "moutarde", "senf", "mostaza", "senape"],
    "kereviz": ["kereviz", "celery", "céleri", "sellerie"],
    "sülfit": ["sülfit", "kükürt dioksit", "kükürtdioksit", "sulfite", "sulphite",
               "sulfur dioxide", "sulphur dioxide", "sulfureux", "solfit",
               "schwefeldioxid",
               "e220", "e221", "e222", "e223", "e224", "e225", "e226",
               "e227", "e228"],
    "lupin": ["acı bakla", "termiye", "lupin", "altramuz"],
}


# ============================================================
# BESİN DEĞERLERİ ve VERİ KALİTESİ
# ============================================================
@dataclass
class Nutrients:
    """100 g (içecekte 100 ml) başına değerler. None = bilinmiyor."""
    energy_kcal: Optional[float] = None
    sugars: Optional[float] = None
    saturated_fat: Optional[float] = None
    sodium_mg: Optional[float] = None
    proteins: Optional[float] = None
    fiber: Optional[float] = None
    fat: Optional[float] = None


# 100 g'da fiziksel olarak mümkün üst sınırlar (saf yağ ~900 kcal, saf tuz
# ~39 300 mg sodyum). Aşan değer etiket ya da veri girişi hatasıdır. Enerjide
# etiket yuvarlamasına (ör. sıvı yağda 902 kcal) küçük pay bırakıldı.
_NUTRIENT_LIMITS = {
    "energy_kcal": 920.0, "sugars": 100.0, "saturated_fat": 100.0,
    "sodium_mg": 39_400.0, "proteins": 100.0, "fiber": 100.0, "fat": 100.0,
}
_CORE_NUTRIENTS = ("energy_kcal", "sugars", "saturated_fat", "sodium_mg", "proteins")


def nutrients_problem(n: Nutrients) -> Optional[str]:
    """Nutri-Score güvenilir hesaplanamıyorsa nedeni, hesaplanabiliyorsa None.

    "missing": zorunlu değerlerden biri (enerji, şeker, doymuş yağ, sodyum,
    protein) yok. Eksik değeri 0 saymak ürünü olduğundan sağlıklı gösterir.
    "implausible": fiziksel olarak imkansız değer kombinasyonu.
    Lif isteğe bağlıdır (etikette zorunlu değil), yoksa 0 puan sayılır.
    """
    if any(getattr(n, k) is None for k in _CORE_NUTRIENTS):
        return "missing"
    for key, limit in _NUTRIENT_LIMITS.items():
        v = getattr(n, key)
        if v is not None and (v < 0 or v > limit):
            return "implausible"
    if n.fat is not None and n.saturated_fat > n.fat + 0.5:
        return "implausible"
    fat = n.fat if n.fat is not None else n.saturated_fat
    if n.sugars + n.proteins + fat > 105:
        return "implausible"
    # Enerji, bildirilen makroların vereceği enerjiden belirgin düşük olamaz
    # (ör. enerji 0 ama şeker 50 g)
    if n.energy_kcal + 20 < 0.8 * (4 * n.sugars + 4 * n.proteins + 9 * fat):
        return "implausible"
    return None


# Adı yoğun bir gıdayı belirten ama enerjisi bunun çok altında kalan ürün
# büyük olasılıkla porsiyon başına girilmiştir (ör. 25 g çikolata = 141 kcal).
# Bu değerlerle not olduğundan iyi çıkar, o yüzden hesaplanmaz. Eşikler
# gerçek 100 g değerlerinin belirgin altında (sütlü çikolata ~540, fındık ~630).
_DENSE_FOODS = (
    (re.compile(r"\b(?:zeytinyagi|zeytin yagi|aycicek yagi|aycicegi yagi|misirozu yagi|"
                r"kanola yagi|findik yagi|susam yagi|olive oil|sunflower oil|"
                r"huile d'olive|huile de tournesol|olivenol)\b"), 700),
    (re.compile(r"\b(?:cikolata|chocolate|chocolat|schokolade)\b"), 300),
    (re.compile(r"\b(?:findik|badem|ceviz|kaju|antep fistigi|yer fistigi|fistik|"
                r"hazelnuts?|almonds?|walnuts?|cashews?|pistachios?|peanuts?)\b"), 350),
    (re.compile(r"\b(?:biskuvi|biscuits?|kraker|crackers?|gofret|wafers?|kurabiye|"
                r"cookies?)\b"), 300),
    (re.compile(r"\b(?:cips|chips|crisps)\b"), 350),
    (re.compile(r"\b(?:toz seker|kup seker|pudra sekeri|granulated sugar)\b"), 350),
)
_DENSE_EXCEPT = re.compile(
    r"dondurma|ice ?cream|gelato|glace|puding|pudding|\bsut\b|\bsutu\b|milk|drink|icecek|"
    r"icecegi|yogurt|kefir|\bsos\b|\bsosu\b|sauce|surup|syrup|\bkek\b|cake|tatli|dessert|"
    r"\bmix\b|karisim|krem\b|smoothie|\bton\b|balik|sardalya|dolma|konserve|"
    r"salata|kizart|yag\w*\s+ile\b|in oil|a l'huile|kahve|coffee|cay\b|\btea\b|ruj|kozmetik|"
    # dondurma/puding markaları ve dolgulu ürünler (gerçek enerjileri düşük)
    r"magnum|carte d'?\s?or|\bgolf\b|algida|cornetto|danette|drancor|plombir|maras|"
    r"panda|kulah|\bcup\b|sandwich|woopie|activia|kruvasan|croissant|recel|"
    r"matcha|\btopu\b|\bball|stick|puresi|puree|sufle|luppo|suyu\b")
# "Fındık aromalı", "çilek & muz aromalı": aroma adı yoğunluk anlatmaz, bu
# kelimeler eşleştirmeden çıkarılır (ürünün kendisi yine kontrol edilir:
# "Portakal Aromalı Çikolata")
_FLAVOUR_PHRASE = re.compile(r"\b\w+(?:\s*(?:&|ve|-|,)\s*\w+)*\s+(?:aromali|aromasi|aroma)\b")


def energy_check_applies(source: Optional[str]) -> bool:
    """Porsiyon başı veri sorunu market kazıma kaynaklarında sistematik; Open
    Food Facts verisinde bu kontrol fazla yanlış alarm verdiği için uygulanmaz."""
    return source in ("getir", "carrefour", "migros")


def energy_implausible_for_name(name: str, energy_kcal: Optional[float]) -> bool:
    """Ürün adına göre enerji olamayacak kadar düşük mü (porsiyon başı veri)?"""
    if energy_kcal is None or not name:
        return False
    s = _FLAVOUR_PHRASE.sub(" ", _fold_ascii(name))
    if _DENSE_EXCEPT.search(s):
        return False
    return any(rx.search(s) and energy_kcal < minimum for rx, minimum in _DENSE_FOODS)


def normalize_sodium_mg(val) -> Optional[float]:
    """Sodyumu mg'a çevir; bilinmiyorsa None.

    Open Food Facts gram verir (0.304 → 304 mg). Bazı market kaynakları mg
    verebiliyor. 100 g'da 90 g sodyum fiziksel olarak imkansız olduğundan
    90'dan küçük değerler gram, büyükler mg kabul edilir.
    """
    if val is None:
        return None
    try:
        v = float(val)
    except (TypeError, ValueError):
        return None
    if v < 0:
        return None
    return v * 1000.0 if v < 90 else v


# ============================================================
# MEYVE / SEBZE / BAKLAGİL ORANI (içindekilerden tahmin)
# ============================================================
# Patates gibi nişastalı yumrular, kuruyemiş ve tahıllar bu gruba girmez.
_FVL_WORDS = (
    r"meyve\w*|fruit\w*|sebze\w*|vegetable\w*|domates\w*|tomato\w*|tomate\w*|"
    r"elma\w*|apple\w*|pomme\w*|armut\w*|pear\b|pears\b|cilek\w*|strawberr\w*|fraise\w*|"
    r"muz\b|muzu\b|banana\w*|banane\w*|portakal\w*|orange\w*|mandalina\w*|mandarin\w*|"
    r"klementin\w*|clementin\w*|greyfurt\w*|grapefruit\w*|pamplemousse\w*|limon\w*|"
    r"lemon\w*|citron\w*|zitron\w*|lime\b|limes\b|misket limon\w*|"
    r"havuc\w*|carrot\w*|carotte\w*|ispanak\w*|spinach\w*|biber\w*|patlican\w*|kabak\w*|"
    r"zucchini\w*|courgette\w*|uzum\w*|grape\w*|raisin\w*|kiraz\w*|visne\w*|cherr\w*|cerise\w*|"
    r"kayisi\w*|apricot\w*|abricot\w*|seftali\w*|peach\w*|peche\w*|incir\w*|fig\b|figs\b|"
    r"nar\b|nari\b|pomegranate\w*|ananas\w*|pineapple\w*|mango\w*|ahududu\w*|raspberr\w*|"
    r"framboise\w*|bogurtlen\w*|blackberr\w*|yaban mersini\w*|blueberr\w*|myrtille\w*|"
    r"cranberr\w*|kizilcik\w*|kivi\w*|kiwi\w*|erik\w*|plum\w*|prune\w*|ayva\w*|hurma\w*|"
    r"karpuz\w*|kavun\w*|melon\w*|pancar\w*|beetroot\w*|betterave\w*|salatalik\w*|cucumber\w*|"
    r"sogan\w*|onion\w*|oignon\w*|sarimsak\w*|garlic\w*|"
    r"bakla\w*|mercimek\w*|lentil\w*|lentille\w*|fasulye\w*|nohut\w*|chickpea\w*|pois chiche\w*|"
    r"bezelye\w*|barbunya\w*|beans?\b|peas\b|pea\b|haricot\w*|"
    r"obst\w*|frucht\w*|fruchte\w*|gemuse\w*|apfel\w*|tomaten\w*|erdbeer\w*|himbeer\w*|"
    r"karotte\w*|zwiebel\w*|linsen\w*|bohnen\w*|erbsen\w*|sinaasappel\w*|manzana\w*|naranja\w*"
)
_FVL_WORD_RE = re.compile(r"\b(?:" + _FVL_WORDS + r")")
# Meyve adı geçen ama meyve/sebze olmayan bileşenler
_FVL_NOT = re.compile(
    r"aroma|flavo|sugar|seker|sucre|zucker|pektin|pectin|protein|lif\b|fiber|fibre|"
    r"cocoa|kakao|coffee|kahve|vanilla|vanilya|jelly|peanut|yag|oil\b|huile|\bol\b|"
    r"nisasta|starch|amidon|unu\b|flour|farine|\bmehl|kabartma|baking|pudra|"
    r"\bcips|chips|crisps|\bsos\b|sauce|\bsirup|surup|syrup|sirop|sirke|vinegar|vinaigre|"
    r"pommes? de terre|patates|potato|kartoffel|pul biber|toz biber|cekirdeg|cekirdek|"
    r"seed|graine|kern")
_PCT = r"(?:%\s*(\d{1,3}(?:[.,]\d+)?)|(\d{1,3}(?:[.,]\d+)?)\s*%)"
_FVL_RE = re.compile(r"\b(?:" + _FVL_WORDS + r")([^,;()\[\]%]{0,30}?)\s*[(\[]?\s*" + _PCT)
# Meyve suyu gibi tek bileşenli listelerde yüzde yazılmaz; yanlarında yalnızca
# bu küçük katkılar olabilir
_FVL_TRIVIAL = re.compile(
    r"^(?:askorbik asit|ascorbic acid|acide ascorbique|sitrik asit|citric acid|acide citrique|"
    r"vitamin\w*|c vitamini|antioksidan\w*|antioxidant\w*|asitlik duzenleyici|acidity regulator|"
    r"acidifiant|pulp|pulpe|posa|e ?3\d\d|dogal aroma\w*|natural flavou?rs?|aroma\w*|"
    r"tuz|salt|sel|su|water|eau|wasser|agua)$")
_ORGANIC = re.compile(r"\b(?:organic|organik|bio|biologique|organique|oko|reconstituted|"
                      r"from concentrate|konsantreden|a base de concentre)\b")
# "portakal suyu", "orange juice", "jus de pomme", "100% orange pulp free juice"
_JUICE_OF = re.compile(
    r"\b(?:" + _FVL_WORDS + r")(?:\s+[a-z]+){0,2}\s+(?:suyu|sulari|juice|juices|saft|sap)\b|"
    r"\b(?:juice|jus|zumo|succo|saft)\s+(?:de\s+|d\s*'\s*|d\s+|di\s+|of\s+|al\s+|von\s+)?"
    r"(?:" + _FVL_WORDS + r")")
_NOT_PURE_JUICE = re.compile(
    r"nektar|nectar|drink|icecek|icecegi|cocktail|beverage|boisson|getrank|bebida|bevanda|"
    r"aroma|flavo|limonata|lemonade|\bade\b|smoothie|sirup|surup|syrup|sirop|shot\b|"
    r"(?<!from )concentrate|konsantre(?:si)?\b|\bin\b|suyunda|surubunda|\bau jus\b|"
    r"jus (?:de |d')?(?:agneau|veau|viande|roti|volaille|boeuf|poulet|cuisson)|"
    r"\bseker|sugar|sucre|zucker|sweet|tatli|light|zero|diet|maden|mineral|soda|\bsu\b|"
    r"water|\beau\b|gazli|sparkling|\b[a-z]+l[iu] (?:[a-z]+ )?(?:suyu|sulari)\b")
_ADDED_SUGAR = re.compile(r"seker|sugar|sucre|zucker|azucar|zucchero|glukoz|glucose|fruktoz|"
                          r"fructose|dekstroz|dextrose|sirup|surup|syrup|sirop|bal\b|honey")
_FVL_ZERO_NAME = re.compile(
    r"\bcips|chips|crisps|popcorn|patlamis misir|pop ?corn|\bflour\b|farine|\bmehl\b|"
    r"\b(?:bugday|misir|pirinc|cavdar|nohut|badem|tam bugday) unu\b|\btofu\b|candied|"
    r"\bconfit|kandiert|sekerleme|sekerlenmis|kuru meyve sekerleme")
_FVL_FULL_OIL = re.compile(
    r"zeytinyagi|zeytin yagi|olive oil|huile d(?:'|e )?\s?olive|aceite de oliva|"
    r"olio d'?\s?oliva|"
    r"olio extra|olivenol|avokado yagi|avocado oil|huile d'?\s?avocat")
_OTHER_OIL = re.compile(
    r"\bcoco|hindistan|aycicek|aycicegi|sunflower|tournesol|colza|kanola|canola|rapeseed|"
    r"misirozu|\bcorn\b|soya|soja|\bsoy\b|palm|blend|karisim|melange|mix|aromali|flavou?red|"
    r"pizza|sprey|spray|\bile\b|\bwith\b|\bet\b|\band\b|&|\bin\b|zeytinyagli|marine|salamura|"
    r"lezzet|taste|gout|geschmack|sabor|margarin|\bmax")
# İçindekilerde başka yağ ya da yüzde sınırı varsa saf zeytinyağı değildir
_OTHER_OIL_INGREDIENT = re.compile(
    r"aycicek|aycicegi|sunflower|tournesol|zonnebloem|sonnenblumen|girasol|colza|raps|"
    r"koolzaad|kanola|canola|rapeseed|misirozu|corn oil|soya|soja|soybean|palm|coco|"
    r"hindistan|max\.?\s*\d|en fazla|\d+\s*%|%\s*\d+")
# "şeker ilavesiz", "no sugar added" şeker eklenmiş sayılmasın
_NO_SUGAR = re.compile(
    r"no (?:added )?sugars?(?: added)?|without (?:added )?sugars?|unsweetened|"
    r"sans sucres? ajoutes?|sans sucres?|seker ilavesiz|ilave seker(?: icermez)?|"
    r"eklenmis seker(?: yok| icermez)?|sekersiz|ohne zucker(?:zusatz)?|"
    r"sin azucar(?:es)?(?: anadidos?)?|senza zuccheri? aggiunti")


def _fold_ascii(text: str) -> str:
    """fold_i + Türkçe ve Avrupa dillerindeki aksanları sadeleştir (eşleştirme için)."""
    return (fold_i(text)
            .translate(str.maketrans("ğüşöçîâéèêëàäôûùáíóúñìòïÿœ", "gusocıaeeeeaaouuaiounioiyo"))
            .replace("ı", "i").replace("ß", "ss").replace("’", "'"))


def _split_ingredients(folded: str) -> List[str]:
    """Üst düzey bileşenler (parantez içleri atılır)."""
    depth, buf, out = 0, [], []
    for ch in folded:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0 and ch in ",;":
            out.append("".join(buf))
            buf = []
        elif depth == 0:
            buf.append(ch)
    out.append("".join(buf))
    cleaned = []
    for part in out:
        part = re.sub(_PCT, " ", part)
        part = _ORGANIC.sub(" ", part)
        part = re.sub(r"[^a-z0-9' ]+", " ", part)
        part = re.sub(r"\s+", " ", part).strip()
        if part:
            cleaned.append(part)
    return cleaned


def fvln_tahmin(text, product_name: str = "") -> float:
    """Meyve/sebze/baklagil oranı tahmini (0-100).

    1. İçindekilerde yüzdesi yazanların toplamı: 'Elma %35, Üzüm %20' → 55
    2. Liste yalnızca meyve/sebze ve küçük katkılardan oluşuyorsa
       (ör. 'Ananas, ananas suyu', 'Orange juice') → 100
    3. Adı katkısız meyve suyu olan ürün (portakal suyu, jus de pomme;
       nektar/içecek/aromalı değil, şeker eklenmemiş) → 100. Yasal tanım
       gereği 'meyve suyu' %100 meyvedir.
    Tahmin edilemeyen durumda düşük kalır; yani not olduğundan iyi çıkmaz.
    """
    folded = _fold_ascii(text or "")
    toplam = 0.0
    for m in _FVL_RE.finditer(folded):
        if _FVL_NOT.search(m.group(0)):
            continue
        num = m.group(2) or m.group(3)
        try:
            toplam += float(num.replace(",", "."))
        except ValueError:
            pass
    toplam = min(toplam, 100.0)

    # OFF kategori kuralları: zeytinyağı/avokado yağı %100, cips, patlamış
    # mısır, un, tofu, şekerlenmiş meyve %0 (taxonomies/food/categories.txt)
    name = _fold_ascii(product_name or "")
    if _FVL_ZERO_NAME.search(name):
        return 0.0
    if (_FVL_FULL_OIL.search(name) and not _OTHER_OIL.search(name)
            and not _OTHER_OIL_INGREDIENT.search(folded)):
        return 100.0
    sugar_added = _ADDED_SUGAR.search(_NO_SUGAR.sub(" ", folded)) is not None
    parts = _split_ingredients(_NO_SUGAR.sub(" ", folded))
    if parts and not sugar_added:
        fvl = [p for p in parts if _FVL_WORD_RE.search(p) and not _FVL_NOT.search(p)]
        rest = [p for p in parts if p not in fvl]
        has_water = any(p in ("su", "water", "eau", "wasser", "agua") for p in rest)
        concentrate = re.search(r"concentr|konsantre", folded)
        if fvl and all(_FVL_TRIVIAL.match(p) for p in rest) and (not has_water or concentrate):
            return 100.0

    if (_JUICE_OF.search(name)
            and not _NOT_PURE_JUICE.search(name) and not sugar_added
            and not _SWEETENER_RE.search(folded)):
        return 100.0
    return toplam


# ============================================================
# NUTRI-SCORE KATEGORİSİ (ürün adından; veri setinde kategori yok)
# ============================================================
@dataclass
class NutriCategory:
    beverage: bool = False
    water: bool = False
    cheese: bool = False
    fat_oil_nuts_seeds: bool = False
    red_meat: bool = False
    not_applicable: bool = False   # Nutri-Score bu ürün grubuna uygulanmaz


# Kategori kuralları Open Food Facts'in yapılandırmasını izler
# (Config_off.pm: categories_exempted_from_nutriscore,
# categories_considered_as_beverages_for_nutriscore_2023; Food.pm). OFF ürünün
# kategori etiketlerini kullanır; bizim veri setimizde yalnızca ad var.
_DRINK_STRONG = re.compile(
    r"\b(?:su|suyu|sulari|soda|gazoz|gazozu|kola|cola|ayran|kefir|limonata|lemonade|"
    r"juice|juices|nektar|nectar|smoothie|drink|drinks|icecek|icecegi|beverage|"
    r"ice ?tea|buzlu cay|soguk cay|milkshake|boisson|getrank|saft|jus|bebida|"
    r"bevanda|zumo|succo|water|eau|wasser|agua|acqua|salgam|boza|kombucha|salep|"
    r"maden suyu|mineral water|sparkling|gazli|energy|enerji|frappe|"
    r"icilebilir|drinkable|trinkjoghurt|batido|hot chocolate|sicak cikolata|chocolat chaud|"
    r"trinkschokolade|bira|beer|biere|bier|malt)\b")
_DRINK_WEAK = re.compile(r"\b(?:sut|sutu|milk|lait|milch|leche|latte|kakao|cocoa|"
                         r"tea|teas|cay|cayi|coffee|kahve|kahvesi|cafe|kaffee|espresso|"
                         r"cappuccino|infusion|tisane|herbal|matcha|chai|rooibos|nescafe)\b|"
                         r"\bthe (?:vert|noir|glace|blanc|earl|menthe|a la|au)\b")
_TEA_COFFEE = re.compile(r"\b(?:tea|teas|cay|cayi|coffee|kahve|kahvesi|kaffee|espresso|"
                         r"cappuccino|infusion|tisane|herbal|matcha|chai|rooibos|nescafe)\b|"
                         r"\bthe (?:vert|noir|glace|blanc|earl|menthe|a la|au)\b")
# Kuru/yoğun biçim: değerler hazırlanmış içecek için verilmişse (≤150 kcal)
# içecek, ürünün kendisi içinse (toz, kapsül...) not hesaplanmaz
_FORM_DRY = re.compile(
    r"\btoz\b|tozu|powder|poudre|pulver|granul|kapsul|capsule|\bpods?\b|cekirdek|\bbeans?\b|"
    r"yaprak|leaves|loose leaf|(?<!from )concentrate|konsantre(?:si)?\b|surup|syrup|sirop|"
    r"sirup|instant|hazir kahve|soluble|\bmix\b|tea bags?|poset|demlik|filtre|ground|"
    r"turk kahvesi|dokme")
# İçecek adı geçse de katı/yenebilir ürünler
_SOLID = re.compile(
    r"\bin (?:[a-z]+ ){0,3}(?:juices?|water|syrup|jus|oil)\b|\bwith (?:[a-z]+ ){0,2}juices\b|"
    r"suyunda|surubunda|surupta|"
    r"dans (?:son|leur|du) jus|\bau jus\b|jus (?:de |d')?(?:agneau|veau|viande|roti|volaille|"
    r"boeuf|poulet|cuisson)|\bbar\b|bari\b|jelly|\bjole\b|\bgum\b|\bsakiz\b|candy|bonbon|"
    r"dondurma|ice ?cream|gelato|\bglace\b|\beis\b|helado|sorbet|\bsticks?\b|lolly|lollipop|"
    r"popsicle|ice pop|crunch|"
    r"(?<!lait )(?<!hot )chocolate?\b(?! (?:milk|drink|shake|milkshake|beverage|latte|chaud))|"
    r"(?<!sicak )cikolata\b|schokolade\b|cioccolato\b")
# Düşük enerjili ama içecek olmayan ürünler (içme yoğurdu, ayran gibi açık
# içecek adları bunları geçersiz kılar)
_NOT_DRINK_SOFT = re.compile(
    r"yogurt|yoghurt|yaourt|joghurt|jogurt|yogur\b|peynir|cheese|fromage|kase\b|kaese|queso|"
    r"puding|pudding|\bflan\b|dessert|muhallebi|sutlac|riz au lait|compote|komposto|"
    r"puree|corba|soup|soupe|suppe|sopa|zuppa|\bsos\b|sauce|recel|\bjam\b|marmelat|"
    r"confiture|ketcap|ketchup|mayonez|mayonnaise|hardal|mustard|krema|\bcream\b|creme|"
    r"kaymak|tereyag|butter|beurre|kraker|cracker|biskuvi|biscuit|kurabiye|cookie|\bkek\b|"
    r"cake|gofret|wafer|ekmek|bread|cereal|gevrek|musli|granola|ezme|spread|"
    r"coconut milk|lait de coco|kokosmilch|hindistan cevizi sutu|condens|kondanse|"
    r"yogunlastirilmis|evaporated|slices|chunks|diced|dilim|konserve|reglisse|lokum|"
    r"helva|borek|pancake|waffle|muffin|brownie")
_DRINK_OVERRIDE = re.compile(
    r"drinking|drinkable|\bdrinks?\b|icecek|icecegi|icilebilir|boisson|getrank|bebida|"
    r"bevanda|trinkjoghurt|ayran|kefir|milkshake|smoothie|yogurt drink|lassi|cream soda|batido")
_PLAIN_WATER = re.compile(r"\b(?:su|suyu|water|eau|wasser|agua|acqua|soda|maden suyu|"
                          r"mineral water|eau minerale|mineralwasser)\b")
_FLAVOURED = re.compile(r"aroma|flavo|meyveli|vitamin|tropical|tropik|nane|mint\b|"
                        r"\bmit\b|\bavec\b|gusto|sabor|\bplus\b|enhancer|electrolyte")
# Adında su/water/soda geçip su olmayanlar: gazoz/tonik (OFF da su saymaz), hindistan
# cevizi suyu, kozmetik (misel suyu, gül suyu), şekerleme ("salt water taffy"), konserve
# ("tuna in water"), kabartma sodası
_NOT_WATER = re.compile(
    r"\b(?:sodas?|tonik|tonic|tonica|tonico|tonique|cola|coco|coconut|kokos|hindistan|"
    r"protein|kefir|micellar|misel|rose|gul|taffy|candy|cream|krem|juice|drinks?|"
    r"tuna|atun|thon|tonno|baking|bicarbonate|karbonat|energy|enerji|prebiotic|"
    r"infused|infusion|cucumber|salatalik|yuzu|berry|citrus|ginger|zencefil|tangerine|"
    r"vanilla|vanilya|lychee|watermelon|karpuz|collagen|kolajen|hops|kewra|orge|barley|"
    r"gripe|taffy|tafy|chestnuts?|lily|alus|micelar|colou?r|boya|plasti[ck]|"
    # gıda olmayan "su"lu ürünler (sıcak su torbası, su bazlı losyon, ağız suyu ...)
    r"sicak|torba|torbasi|termos|mop|pompa|pompasi|tabanca|bazli|losyon|agiz|makyaj|"
    r"temizleme|aerosol|sprey|spray|toilet|toiletblok|softener|yumusatici|"
    r"hipertonica|mar)\b")
# Besin tablosu olmayan su ancak adı açıkça sade su ise A alır (marketler sade suya çoğu
# zaman besin tablosu koymuyor)
_CLEAR_WATER = re.compile(
    r"\b(?:maden|kaynak|icme|memba|mineralli|ambalajli|dogal) su(?:yu)?\b|\bpure life\b|"
    r"\bagua\b.*\bmanantial\b|"
    r"\b(?:mineral|mineraal|spring|natural|purified|drinking|table|still|sparkling|artesian|"
    r"distilled|alkaline|glacier|mountain|bottled|pure|carbonated) water\b|"
    r"\beau (?:minerale?|mineralle|de source|de table|plate|gazeuse|petillante|de montagne)\b|"
    r"\b(?:mineral|tafel|quell)wasser\b|"
    r"\bagua (?:mineral|mineralizada|de mesa|con gas|sin gas|pura|purificada|de nascente|"
    r"natural)\b|"
    r"\bacqua (?:minerale|naturale|frizzante|oligominerale|effervescente)\b")
_WATER_WORDS = {"su", "suyu", "water", "eau", "wasser", "agua", "acqua"}
_PACK_WORDS = {"l", "lt", "ml", "cl", "x", "litre", "liter", "pet", "sise", "cam", "damacana",
               "paket", "paketi", "pack", "bottle", "adet", "koli", "li", "lu", "lik"}


def _clearly_water(s: str) -> bool:
    """Ad, marka ve ambalaj dışında yalnız 'su' diyor mu ("Damla Su 1,5 L", "Fiji Water")."""
    if _CLEAR_WATER.search(s):
        return True
    words = [w for w in re.findall(r"[a-z]+", s)
             if len(w) > 1 and w not in _WATER_WORDS and w not in _PACK_WORDS]
    return len(words) <= 2
# OFF'ta Nutri-Score hesaplanmayan gruplar: alkollü içecekler, bebek gıdaları,
# sakız, katkı maddeleri, takviyeler, öğün yerine geçenler, tuz, baharat,
# tatlandırıcı, sirke
_NOT_APPLICABLE = re.compile(
    r"\bbira\b|\bbeer\b|\bbiere\b|\bbier\b|\bsarap|\bwine\b|\bvin\b|\bwein\b|"
    r"\braki\b|vodka|whisk|\bgin\b|\brum\b|likor|liqueur|cognac|tequila|\bcidre\b|"
    r"bebek mamasi|devam sutu|bebek bisku|\bbebe\b|infant|baby food|babynahrung|ek gida|"
    r"takviye|supplement|multivitamin|kapsul|capsule|softgel|efervesan|effervescent|"
    r"meal replacement|substitut de repas|mahlzeitenersatz|ogun yerine|"
    r"chewing gum|bubble gum|\bsakiz\b|kabartma tozu|baking powder|backpulver|levure chimique|"
    r"\btatlandirici\b|sweetener|sucrette|canderel|stevia (?:tablet|toz|powder|drops|damla)|"
    r"\bbaharat(?:i|lar|lari)?\b|\bspices?\b(?! latte| cake| cookie| tea| chai)|"
    r"\bkekik\b|\bkarabiber\b|\bpul biber\b|\bkimyon\b|\bsumak\b|\bzerdecal\b|\btarcin\b|"
    r"\bzencefil\b|\bkori\b|\bkoriander\b|curry powder|\bherbes de provence|"
    r"dried herbs|mixed herbs|\bsirkesi?\b|vinegar|vinaigre\b|essig\b|aceto\b|"
    r"\b(?:sofra|kaya|deniz|iyotlu|himalaya|granul|tablet)\s+tuzu\b|^tuz\b|"
    r"\b(?:sea|table|rock|himalayan|kosher|iodized|pink)\s+salt$|^salt$")
_NOT_APPLICABLE_EXCEPT = re.compile(
    r"alkolsuz|alcohol.free|non.alcoholic|sans alcool|alkoholfrei|\b0[.,]0\b|"
    r"cips|chips|crisps|kraker|cracker|popcorn|pretzel|\bnuts?\b|soslu|marine|"
    r"spice latte|ginger ?ale|zencefilli|tarcinli")
_CHEESE = re.compile(
    r"peynir|cheese|fromage|kase\b|kaese|\bqueso|formaggio|kasar|\blor\b|labne|"
    r"tulum|hellim|halloumi|mozzarella|cheddar|parmesan|parmigiano|gouda|\bedam|"
    r"emmental|\bbrie\b|camembert|\bfeta\b|ricotta|mascarpone|gorgonzola|roquefort|"
    r"mihalic|cecil|coulommiers|reblochon|\bcomte\b|beaufort|munster|\btomme\b|raclette|"
    r"morbier|cantal|chevre|pecorino|manchego|grana padano|provolone|gruyere|appenzell|"
    r"leerdammer|maasdam|stilton|havarti|\bbleu d")
_NOT_CHEESE = re.compile(
    r"peynirl[iu]|kasarl[iu]|kraker|cracker|cips|chips|borek|pizza|sandvic|"
    r"sandwich|\btost|toast|\bsos\b|sauce|soslu|\bpuf|puff|\bballs?\b|\bkek\b|cake|"
    r"makarna|pasta\b|burger|pogaca|simit|biskuvi|biscuit|crisps|snack|popcorn|"
    r"nachos|cerez|gofret|kurabiye|cookie|\bdip\b|\bmix\b|lasagn|quiche|tart\b|"
    r"cheesecake|frosting|macaroni|mac and|omelet|krep|gozleme|ravioli|tortellini|"
    r"fromage blanc|fromage frais|faisselle|petit.suisse|quark|skyr|tourteau|gateau|tarte\b|"
    r"yogurt|yoghurt|yaourt|alternative|vegan|plant|bitkisel|"
    # "peynir aromalı", "au fromage", "3 fromages": peynirin kendisi değil
    r"\bgout\b|\bgusto\b|flavou?r|aroma|saveur|geschmack|sabor|\bkit\b|lunch|brochette|"
    r"volaille|poulet|chicken|tavuk|cordon bleu|gratin|au fromage|aux fromages|"
    r"\d+ fromages|quatre fromages|formaggi\b|with cheese|and cheese|& cheese|sauce|dip")
_RED_MEAT = re.compile(
    r"sucuk|salam|sosis|pastirma|kavurma|kiyma|\bdana|sigir|\bkuzu|koyun|\bbeef|"
    r"\bveal|\bpork|\blamb|mutton|\bham\b|jambon|bacon|chorizo|salami|wurst|saucisse|"
    r"saucisson|steak|biftek|kebap|doner|kofte|hamburger|pepperoni|prosciutto|speck|"
    r"mortadella|bresaola|\brind|schwein|\bporc|boeuf|agneau")
_NOT_RED_MEAT = re.compile(
    r"tavuk|pilic|hindi|chicken|turkey|poulet|dinde|pollo|hahnchen|huhn|\bpute|"
    r"balik|fish|\bton\b|somon|salmon|vegan|vejetaryen|vegetari|veggie|bitkisel|"
    r"plant|\bsoya|tofu|\bjus\b|gravy|bouillon|\bstock\b|\bbulyon|cesni|aroma|flavo|"
    r"ravioli|tortellini|manti|pizza|lasagn|burrito|sandwich|sandvic|wrap|soup|corba|"
    r"noodle|makarna|pasta\b|borek|pide|lahmacun|\btost|pogaca|cips|chips|crisps|"
    r"sauce|\bsos\b|cheese|peynir|croissant|quiche|crepe|krep|feuillete|empanada|"
    r"\bsnack|combo|\bkit\b")
_FATS_NUTS = re.compile(
    r"zeytinyagi|zeytin yagi|aycicek yagi|aycicegi yagi|misirozu yagi|kanola yagi|"
    r"findik yagi|susam yagi|tereyagi|tereyag\b|margarin|\boil\b|olive oil|huile|"
    r"\bol\b|olivenol|\bbutter\b|\bbeurre\b|mantequilla|\bburro\b|ghee|sade yag|"
    r"\bkuruyemis\b|"   # "Karışık Kuruyemiş" (kuruyemişli bar/granola dışarıda kalır)
    r"\bfindik\b|findigi|\bbadem\b|bademi|\bceviz\b|cevizi|\bfistik\b|fistigi|\bkaju\b|"
    r"cekirdegi|cekirdek ici|\bnuts?\b|almonds?\b|walnuts?\b|hazelnuts?\b|peanuts?\b|"
    r"cashews?\b|pistachios?\b|pecans?\b|macadamia|\bseeds?\b|graines|\btahin|"
    r"\bnoix\b|amandes|noisettes|cacahuetes|nusse\b|mandeln|erdnusse|"
    # OFF'ta kremalar da bu grupta (en:creams)
    r"\bkrema\b|\bkremasi\b|\bkaymak\b|\bcream\b|creme fraiche|creme (?:epaisse|liquide|"
    r"entiere|legere|fleurette)|\bsahne\b|schlagsahne|\bnata\b|\bpanna\b")
_NOT_FATS_NUTS = re.compile(
    # "Antep fıstığı aromalı mısır çerezi": fıstık ürünün kendisi değil, tadı
    # ("tütsü aromalı karışık kuruyemiş" ise kuruyemiştir, eşleşmez)
    r"(?:findik\w*|badem\w*|ceviz\w*|fistig?\w*|kaju|tahin\w*|krema\w*|kaymak\w*|"
    r"tereyag\w*|butter|cream) (?:aromali|aromasi)|"
    r"cikolata|chocolat|\bchoco|kakao|cocoa|gofret|wafer|kestane|chestnut|chataigne|marron|"
    r"petit beurre|financier|gateau|madeleine|croissant|patisserie|pastry|\bsable|galette|"
    r"buchette|brioche|\bpie\b|\btart|muffin|brownie|"
    r"\bbar\b|bari\b|\bkek\b|cake|biskuvi|biscuit|kurabiye|cookie|dondurma|"
    r"ice ?cream|sutu\b|\bmilk\b|\bdrink|icecek|helva|lokum|baklava|"
    r"cereal|gevrek|musli|granola|ekmek|bread|sos\b|sauce|in oil|zeytinyagli|"
    r"yagli\b|yagsiz|shortbread|popcorn|cips|chips|pesto|"
    r"peanut butter cup|fistik ezmeli|tuna|ton balig|sardalya|sardine|dessert|tatli|"
    r"lait de coco|coconut milk|yaourt|yogurt|yoghurt|pudding|puding|cream cheese|"
    r"krem peynir|cream soda|soup|corba|findik kremasi|fistik kremasi|pastacilik|"
    r"karamel|caramel|vanilla|vanilya|sekerli|santi|liqueur|likor|filled|dolgulu|"
    r"cracker|kraker|pasta kremasi|a l'?\s?huile|in (?:olive |sunflower )?oil|\bthon\b|"
    r"\btonno\b|toffee|honey roasted|kaplamali|coated|enrobe|candied|praline|pralin")


def _fat_dominant(n: Optional[Nutrients], s: str = "") -> bool:
    """Yağ/kuruyemiş/tohum grubu enerjisinin çoğu yağdan gelen ürünler içindir
    (kuruyemiş ~%75, tohum %55+, ezme, sıvı yağ, tereyağı, krema %85+). Adında
    fındık/badem/krema geçse de enerjisi şekerden ya da nişastadan gelen ürün (badem
    aromalı gazoz, ceviz reçeli, fındıklı yoğurt kasesi, fıstıklı dondurma, tohumlu
    pirinç patlağı) genel gruptadır. Değer yoksa ada güvenilir. Adı açıkça
    "kuruyemiş" olan karışımda (leblebi, kaplamalı fıstık içerebilir) yağ oranı
    düşük çıkabilir; o yalnız şeker sınırına bakar."""
    if n is None or not n.energy_kcal or n.energy_kcal <= 0:
        return True
    e = n.energy_kcal
    if n.sugars is not None and 4 * n.sugars > 0.3 * e:
        return False
    if n.fat is not None and 9 * n.fat < 0.45 * e and "kuruyemis" not in s:
        return False
    return True


def nutri_category(name: str, n: Optional[Nutrients] = None,
                   sweeteners: bool = False) -> NutriCategory:
    """Ürün adından (ve besin değerlerinden) Nutri-Score kategorisini tahmin et."""
    s = _fold_ascii(name or "")
    cat = NutriCategory()
    energy = n.energy_kcal if n is not None else None
    if _NOT_APPLICABLE.search(s) and not _NOT_APPLICABLE_EXCEPT.search(s):
        cat.not_applicable = True
        return cat
    if n is not None and n.sodium_mg is not None and n.sodium_mg >= 30_000:
        cat.not_applicable = True          # %75+ tuz: sofra tuzu, bulyon tozu vb.
        return cat
    # 100 ml'de 150 kcal üstü içecek neredeyse yok (milkshake ~100, tam yağlı süt ~65)
    liquid_energy = energy is None or energy <= 150
    drinkish = (_DRINK_OVERRIDE.search(s) or _DRINK_STRONG.search(s) or _DRINK_WEAK.search(s))
    if drinkish and not _SOLID.search(s):
        if _FORM_DRY.search(s) and not _NOT_DRINK_SOFT.search(s):
            # Toz/kapsül/çekirdek: değerler hazırlanmış içecek içinse içecek,
            # ürünün kendisi içinse (yüksek enerji) içecek notu anlamsız
            if liquid_energy:
                cat.beverage = True
            else:
                cat.not_applicable = True
                return cat
        elif _DRINK_OVERRIDE.search(s) or not _NOT_DRINK_SOFT.search(s):
            if liquid_energy:
                cat.beverage = True
            elif _TEA_COFFEE.search(s):
                cat.not_applicable = True   # kuru çay/kahve değerleri
                return cat
    if cat.beverage and n is not None and not sweeteners:
        if (_PLAIN_WATER.search(s) and not _FLAVOURED.search(s) and not _FVL_WORD_RE.search(s)
                and not _NOT_WATER.search(s) and (n.sugars or 0) <= 0.1):
            if energy is not None:
                cat.water = energy <= 1
            else:
                # Su notu (A) eksik veri kontrolünden önce verilir: enerjisi bilinmeyen
                # üründe yalnız adı açıkça sade su olan ve bilinen makroları ~0 olan
                cat.water = (_clearly_water(s) and max(n.proteins or 0, n.fat or 0,
                                                        n.saturated_fat or 0) <= 0.5)
    if not cat.beverage:
        if _CHEESE.search(s) and not _NOT_CHEESE.search(s):
            cat.cheese = True
        elif _FATS_NUTS.search(s) and not _NOT_FATS_NUTS.search(s) and _fat_dominant(n, s):
            cat.fat_oil_nuts_seeds = True
        if _RED_MEAT.search(s) and not _NOT_RED_MEAT.search(s):
            cat.red_meat = True
    return cat


def is_beverage(product_name: str, energy_kcal: Optional[float] = None) -> bool:
    """Ürün adından içecek olup olmadığı (porsiyon birimi ml/g için)."""
    return nutri_category(product_name, Nutrients(energy_kcal=energy_kcal)).beverage


_SWEETENER_RE = re.compile(
    r"\be ?9(?:50|51|52|54|55|57|59|60[a-d]?|61|62|69)\b|aspartam|asesulfam|acesulfam|"
    r"sukraloz|sucralose|sakarin|saccharin|siklamat|cyclamate|steviol|stevia|neotam|"
    r"advantam|taumatin|thaumatin|neohesperidin")


def has_non_nutritive_sweeteners(ingredients: str = "", additives_tags=None) -> bool:
    """Tatlandırıcı (aspartam, sukraloz, steviol...) içeriyor mu?
    additives_tags: "en:e330,en:e951" gibi metin ya da liste."""
    if _SWEETENER_RE.search(_fold_ascii(ingredients or "")):
        return True
    if isinstance(additives_tags, str):
        additives_tags = additives_tags.split(",")
    for tag in additives_tags or ():
        if re.search(r"e9(?:50|51|52|54|55|57|59|60[a-d]?|61|62|69)[a-z]*$", str(tag).strip().lower()):
            return True
    return False


# ============================================================
# NUTRI-SCORE 2023 — Open Food Facts'in açık kaynak uygulamasıyla
# (ProductOpener/Nutriscore.pm) aynı eşikler ve kurallar
# ============================================================
_NS_THRESHOLDS = {
    "energy": [335, 670, 1005, 1340, 1675, 2010, 2345, 2680, 3015, 3350],     # kJ
    "energy_beverages": [30, 90, 150, 210, 240, 270, 300, 330, 360, 390],
    "sugars": [3.4, 6.8, 10, 14, 17, 20, 24, 27, 31, 34, 37, 41, 44, 48, 51],  # g
    "sugars_beverages": [0.5, 2, 3.5, 5, 6, 7, 8, 9, 10, 11],
    "saturated_fat": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],                          # g
    "salt": [0.2, 0.4, 0.6, 0.8, 1, 1.2, 1.4, 1.6, 1.8, 2,
             2.2, 2.4, 2.6, 2.8, 3, 3.2, 3.4, 3.6, 3.8, 4],                      # g
    "energy_from_saturated_fat": [120, 240, 360, 480, 600, 720, 840, 960, 1080, 1200],
    "saturated_fat_ratio": [10, 16, 22, 28, 34, 40, 46, 52, 58, 64],          # %
    "fruits_vegetables_legumes": [40, 60, 80, 80, 80],                         # %
    "fruits_vegetables_legumes_beverages": [40, 40, 60, 60, 80, 80],
    "fiber": [3.0, 4.1, 5.2, 6.3, 7.4],                                        # g
    "proteins": [2.4, 4.8, 7.2, 9.6, 12, 14, 17],                              # g
    "proteins_beverages": [1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0],
}


def _ns_points(table: str, value: Optional[float], beverage: bool) -> int:
    if value is None:
        return 0
    key = table + "_beverages" if beverage and table + "_beverages" in _NS_THRESHOLDS else table
    if table == "saturated_fat_ratio":   # bu tabloda eşik dahil (>=)
        return sum(1 for t in _NS_THRESHOLDS[key] if value >= t)
    return sum(1 for t in _NS_THRESHOLDS[key] if value > t)


def _ns_grade(score: int, cat: NutriCategory) -> str:
    if cat.beverage:
        if cat.water:
            return "A"
        return "B" if score <= 2 else "C" if score <= 6 else "D" if score <= 9 else "E"
    if cat.fat_oil_nuts_seeds:
        return ("A" if score <= -6 else "B" if score <= 2 else "C" if score <= 10
                else "D" if score <= 18 else "E")
    return ("A" if score <= 0 else "B" if score <= 2 else "C" if score <= 10
            else "D" if score <= 18 else "E")


@dataclass
class NutriScoreResult:
    grade: Optional[str]          # "A".."E"; None = hesaplanamadı
    score: Optional[int]
    breakdown: dict
    category: NutriCategory
    source: str = "computed"      # "computed" (bu API) | "official" (Open Food Facts)
    unavailable_reason: Optional[str] = None   # not_applicable | missing | implausible

    @property
    def category_name(self) -> str:
        c = self.category
        if c.water:
            return "water"
        if c.beverage:
            return "beverage"
        if c.cheese:
            return "cheese"
        if c.fat_oil_nuts_seeds:
            return "fat_oil_nuts_seeds"
        if c.red_meat:
            return "red_meat"
        return "general"

    def to_dict(self) -> dict:
        return {"grade": self.grade, "points": self.score, "breakdown": self.breakdown,
                "category": self.category_name, "source": self.source,
                "unavailable_reason": self.unavailable_reason}


def estimate_fat(n: Nutrients) -> Optional[float]:
    """Toplam yağ bilinmiyorsa enerjiden tahmin (yağ/kuruyemiş grubunda
    doymuş yağ oranı için). Şeker dışı karbonhidrat bilinmediğinden yağ biraz
    fazla tahmin edilebilir; sıvı yağlarda karbonhidrat olmadığı için kesindir."""
    if n.energy_kcal is None or n.saturated_fat is None:
        return None
    est = (n.energy_kcal - 4 * (n.proteins or 0) - 4 * (n.sugars or 0)) / 9
    return max(n.saturated_fat, min(est, 100.0))


def _breakdown(n: Nutrients, points: dict, fvl_pct: Optional[float],
               sweeteners: Optional[bool]) -> dict:
    """Uygulamanın gösterdiği döküm. Olumlu bileşenlerin puanı eksi işaretli;
    puanların toplamı her zaman toplam puana eşittir."""
    def p(key):
        v = points.get(key)
        return None if v is None else int(v)

    def neg(key):
        v = p(key)
        return None if v is None else -v

    def shown(attr):
        # Fiziksel olarak imkansız değer gösterilmez (bilinmiyor sayılır)
        v = getattr(n, attr)
        if v is None or v < 0 or v > _NUTRIENT_LIMITS[attr]:
            return None
        return round(v, 2)

    return {
        "energy": {"value": shown("energy_kcal"), "unit": "kcal", "points": p("energy")},
        "sugars": {"value": shown("sugars"), "unit": "g", "points": p("sugars")},
        "saturated_fat": {"value": shown("saturated_fat"), "unit": "g",
                          "points": p("saturated_fat")},
        "sodium": {"value": shown("sodium_mg"), "unit": "mg", "points": p("salt")},
        "sweeteners": {"value": sweeteners, "unit": "", "points": p("sweeteners")},
        "proteins": {"value": shown("proteins"), "unit": "g", "points": neg("proteins")},
        "fiber": {"value": shown("fiber"), "unit": "g", "points": neg("fiber")},
        "fruits_vegetables_legumes": {"value": fvl_pct, "unit": "%",
                                      "points": neg("fruits_vegetables_legumes")},
    }


def compute_nutri_score(n: Nutrients, cat: NutriCategory, fvl_pct: float = 0.0,
                        sweeteners: bool = False) -> NutriScoreResult:
    """Nutri-Score 2023. Hesaplanamıyorsa (uygulanmaz, eksik ya da imkansız
    veri) grade=None ve nedeni döner: yanlış not göstermek, not
    göstermemekten kötüdür."""
    empty = _breakdown(n, {}, None, None)
    if cat.not_applicable:
        return NutriScoreResult(None, None, empty, cat, unavailable_reason="not_applicable")
    bev = cat.beverage
    if cat.water:
        zero = {k: 0 for k in ("energy", "sugars", "saturated_fat", "salt", "sweeteners",
                               "proteins", "fiber", "fruits_vegetables_legumes")}
        return NutriScoreResult("A", 0, _breakdown(n, zero, 0.0, False), cat)
    problem = nutrients_problem(n)
    if problem:
        return NutriScoreResult(None, None, empty, cat, unavailable_reason=problem)

    if cat.fat_oil_nuts_seeds:
        fat = n.fat if n.fat is not None else estimate_fat(n)
        pts_energy = _ns_points("energy_from_saturated_fat", n.saturated_fat * 37, bev)
        ratio = (n.saturated_fat / fat * 100) if fat else 0.0
        pts_satfat = _ns_points("saturated_fat_ratio", ratio, bev)
    else:
        pts_energy = _ns_points("energy", n.energy_kcal * 4.184, bev)
        pts_satfat = _ns_points("saturated_fat", n.saturated_fat, bev)
    pts_sugars = _ns_points("sugars", n.sugars, bev)
    pts_salt = _ns_points("salt", n.sodium_mg * 2.5 / 1000, bev)
    pts_sweet = 4 if bev and sweeteners else 0
    negative = pts_energy + pts_sugars + pts_satfat + pts_salt + pts_sweet

    pts_fvl = _ns_points("fruits_vegetables_legumes", fvl_pct, bev)
    pts_fiber = _ns_points("fiber", n.fiber, bev)
    pts_proteins = _ns_points("proteins", n.proteins, bev)
    if cat.red_meat and pts_proteins > 2:
        pts_proteins = 2
    if bev or cat.cheese:
        count_proteins = True
    elif cat.fat_oil_nuts_seeds:
        count_proteins = negative < 7
    else:
        count_proteins = negative < 11
    if not count_proteins:
        pts_proteins = 0

    score = negative - (pts_fvl + pts_fiber + pts_proteins)
    points = {"energy": pts_energy, "sugars": pts_sugars, "saturated_fat": pts_satfat,
              "salt": pts_salt, "sweeteners": pts_sweet, "proteins": pts_proteins,
              "fiber": pts_fiber, "fruits_vegetables_legumes": pts_fvl}
    return NutriScoreResult(_ns_grade(score, cat), score,
                            _breakdown(n, points, fvl_pct, sweeteners), cat)


def evaluate_nutri_score(name: str, n: Nutrients, ingredients: str = "",
                         additives_tags=None, data_source: Optional[str] = None
                         ) -> NutriScoreResult:
    """Ürün adı + besin değerleri + içindekilerden Nutri-Score (arama ve
    barkod aynı fonksiyonu kullanır, sonuçlar tutarlı kalır)."""
    sweet = has_non_nutritive_sweeteners(ingredients, additives_tags)
    cat = nutri_category(name, n, sweet)
    if (not cat.not_applicable and not cat.beverage and energy_check_applies(data_source)
            and energy_implausible_for_name(name, n.energy_kcal)):
        return NutriScoreResult(None, None, _breakdown(n, {}, None, None), cat,
                                unavailable_reason="implausible")
    return compute_nutri_score(n, cat, fvln_tahmin(ingredients, name), sweet)


def nutri_score_from_off(product: dict, n: Nutrients) -> Optional[NutriScoreResult]:
    """Open Food Facts'in kendi hesapladığı 2023 notu (ürünün kategori
    etiketlerine dayanır, bizim ad tahminimizden güvenilirdir). OFF not
    hesaplamadıysa None."""
    ns = ((product or {}).get("nutriscore") or {}).get("2023") or {}
    grade = str(ns.get("grade") or "").lower()
    if not ns.get("nutriscore_computed") or grade not in ("a", "b", "c", "d", "e"):
        return None
    if not isinstance(ns.get("score"), (int, float)):
        return None
    d = ns.get("data") or {}
    comps = d.get("components") or {}
    points, values = {}, {}
    for side in ("negative", "positive"):
        for c in comps.get(side) or ():
            points[c.get("id")] = c.get("points")
            values[c.get("id")] = c.get("value")
    # yağ grubunda enerji/doymuş yağ satırları farklı bileşenlerden gelir
    if "energy" not in points:
        points["energy"] = points.get("energy_from_saturated_fat")
    if "saturated_fat" not in points:
        points["saturated_fat"] = points.get("saturated_fat_ratio")
    points["sweeteners"] = points.get("non_nutritive_sweeteners", 0)
    cat = NutriCategory(beverage=bool(d.get("is_beverage")), water=bool(d.get("is_water")),
                        cheese=bool(d.get("is_cheese")),
                        fat_oil_nuts_seeds=bool(d.get("is_fat_oil_nuts_seeds")),
                        red_meat=bool(d.get("is_red_meat_product")))
    fvl = values.get("fruits_vegetables_legumes")
    sweet = values.get("non_nutritive_sweeteners")
    total = sum(v for v in (points.get(k) for k in (
        "energy", "sugars", "saturated_fat", "salt", "sweeteners")) if v) - sum(
        v for v in (points.get(k) for k in ("proteins", "fiber", "fruits_vegetables_legumes")) if v)
    if total != int(ns["score"]):
        # Bileşenler toplamı tutmuyorsa (eski/eksik kayıt) dökümü gösterme
        points = {}
    return NutriScoreResult(grade.upper(), int(ns["score"]),
                            _breakdown(n, points, fvl, bool(sweet) if sweet is not None else None),
                            cat, source="official")


# ============================================================
# ALERJEN TESPİTİ
# ============================================================
# Metin ve keyword'ler _fold_ascii ile sadeleştirilir: "BLE" = "blé",
# "yogurt" = "yoğurt", "FINDIK" = "fındık".
#
# Keyword türleri:
#  - Türkçe kısa kökler ekleriyle: "inek sütü", "sütlü", "sütten", "arpalı";
#    yokluk eki ("sütsüz") ve başka kelimeler ("arpacık") eşleşmez
#  - Bileşik kelimelerin başı: "soybean", "sojalecithin", "melkpoeder", "milkfat"
#  - Diğer kısa kelimeler yalnızca tam kelime (+ çoğul s): "cod" ≠ "code",
#    "egg" ≠ "eggplant", "nut" ≠ "coconut"
#  - Uzun keyword'ler kelime içinde de aranır ("weizenmehl", "fındıklı")
_ALLERGEN_SUFFIX = r"(?:s|[iu]|l[iu]|y[ae]|[ae]|[dt][ae]n?|l[ae]r|s[iu]|n[iu]n)?"
_TR_SHORT_KEYWORDS = {"sut", "arpa", "kaju"}
_PREFIX_KEYWORDS = {"soy", "soja", "soia", "melk", "kaas", "oat", "eier", "milk", "whey"}
_WHOLE_WORD_KEYWORDS = {"spelt", "latte", "haring"}   # "geraspelt", "sharing"

# Keyword'den hemen sonra gelirse alerjenin YOKLUĞUNU anlatan ifadeler:
# "glutensiz", "gluten içermez", "gluten-free", "glutenfrei"
_NEGATION_AFTER = re.compile(r"\s*-?\s*(?:s[iu]z|free\b|frei\b|icerme|bulunmaz)")

# Keyword'den hemen ÖNCE gelirse yokluk anlatan ifadeler:
# "sans gluten", "sin gluten", "senza latte", "ohne milch", "without egg",
# "no milk", "free from gluten"
_NEGATION_BEFORE = re.compile(
    r"\b(?:sans|sin|senza|ohne|without|no|free\s+from)\s*[:\-]?\s*$")

# Glutensiz tahıl/baklagil unları: "rice flour", "mısır irmiği" gluten değil
_NON_GLUTEN_BEFORE = re.compile(
    r"\b(?:rice|corn|maize|chickpea|gram|soy\w*|coconut|almond|potato|tapioca|"
    r"cassava|manioc|pea|lentil|bean|fava|quinoa|millet|sorghum|teff|banana|"
    r"chestnut|carob|hemp|flax\w*|linseed|sunflower|arrowroot|peanut|nut|hazelnut|"
    r"cashew|amaranth|lupin\w*|cricket|yam|konjac|guar|sago|karab|pirinc|misir|"
    r"nohut|patates|mercimek|keciboynuzu|kestane)\s+(?:\w+\s+)?$")
_EXCLUDE_BEFORE = {
    "flour": _NON_GLUTEN_BEFORE, "semolina": _NON_GLUTEN_BEFORE,
    "irmik": _NON_GLUTEN_BEFORE, "irmig": _NON_GLUTEN_BEFORE,
    # "sert kabuklu(lar)" = kuruyemiş; "kabuklular" tek başına = kabuklu deniz ürünü
    "kabuklular": re.compile(r"\bsert\s*$"),
}

# Alerjen keyword'ü içeren ama alerjen olmayan kalıplar (sadeleştirilmiş metinde)
_NON_ALLERGEN_SUBS = tuple((re.compile(p), r) for p, r in (
    # Hindistan cevizi AB/TGK alerjen listesinde yok ("küçük hindistan cevizi" = muskat)
    (r"hindistan\s*cevizi?(?:\s*(?:sutu|kremasi|yagi|suyu|unu|rendesi))?", "kokos"),
    (r"noix de coco|noix de muscade|muskat cevizi", "kokos"),
    (r"\bcoconut\s+(?:milk|cream|drink|butter)", "coconut"),
    (r"\b(?:lait|leche|latte|creme)\s+(?:de\s+|di\s+|d')?(?:coco|cocco)\b", "coco"),
    # Bitkisel "süt"ler süt alerjeni değil (bitkinin kendisi ayrıca eşleşir)
    (r"\b(badem|soya|yulaf|pirinc|findik|kaju|almond|soy|oat|rice|cashew|hazelnut|hemp)"
     r"\s+(?:sutu|milk|drink|icecegi)\b", r"\1"),
    (r"\b(?:lait|leche|latte)\s+(?:de\s+|di\s+|d')(amande|soja|avoine|riz|almendra|avena|"
     r"arroz|mandorla|soia|riso|noisette|avellana)\b", r"\1"),
    (r"(mandel|soja|hafer|reis|kokos|dinkel)milch", r"\1"),
    # Adında "butter/beurre" geçen ama süt içermeyenler
    (r"\b(cocoa|cacao|shea|peanut|almond|cashew|hazelnut|nut|seed|sunflower|apple)\s+butter",
     r"\1"),
    (r"\bbeurre\s+(?:de\s+|d')(cacao|karite|arachide|cacahuete)", r"\1"),
    (r"(kakao|erdnuss)butter", r"\1"),
    (r"\bbutter\s*beans?\b|\bbutternut", "lima"),
    (r"cream of tartar|cream soda", "tartar"),
    (r"milchsaure|melkzuur", "lsaure"),            # laktik asit
    (r"karabugday|buckwheat|buchweizen|ble noir", "karab"),   # karabuğday glutensiz
    (r"(glutensiz|gluten[\s\-]*free|glutenfrei\w*|sans gluten|sin gluten|senza glutine)"
     r"\s+(?:yulaf\w*|oat\w*|hafer\w*|avoine|avena)", r"\1 tahil"),
    # Sülfitli/amonyak karamel (E150b/d) sülfit alerjeni değil
    (r"(?:amonyak\w*|amonyum|ammoni\w*|kostik|caustic|kaustik)[\s\-]*(?:sulfit|sulphit)\w*",
     "karamel"),
    (r"(?:sulfit|sulphit)\w*[\s\-]+(?:(?:amonyak|ammoni)\w*[\s\-]+)?(?:karamel|caramel)",
     "karamel"),
    (r"\bbalik\s*(?:kraker|sekl)\w*", "kraker"),   # balık şeklinde kraker
    (r"balikesir", "bkesir"),
    (r"(?:oyster|istiridye)\s+(?:mushroom|mantar)\w*", "pleurotus"),
    (r"tintenfisch", "tinten mollus"),
    (r"\b(chocolate|cikolata\w*|surpriz|easter|paskalya)\s+(?:eggs?|yumurta\w*)", r"\1"),
))
_E_NUMBER_SPACE = re.compile(r"\be[\s\-]+(\d{3})\b")


def _keyword_pattern(kw: str) -> str:
    if kw in _PREFIX_KEYWORDS:
        return r"\b" + re.escape(kw) + r"\w*"
    if kw in _TR_SHORT_KEYWORDS:
        return r"\b" + re.escape(kw) + _ALLERGEN_SUFFIX + r"\b"
    if len(kw) <= 4 or kw in _WHOLE_WORD_KEYWORDS:
        return r"\b" + re.escape(kw) + r"s?\b"
    return re.escape(kw)


_ALLERGEN_PATTERNS = tuple(
    (allergen, tuple((re.compile(_keyword_pattern(k)), _EXCLUDE_BEFORE.get(k))
                     for k in dict.fromkeys(_fold_ascii(kw) for kw in keywords)))
    for allergen, keywords in ALLERGENS.items())


def _allergen_text(text: str) -> str:
    # OFF alerjenleri _alt çizgi_ / *yıldız* ile vurgular; "_" kelime karakteri
    # olduğundan kelime sınırını bozar
    t = re.sub(r"[_*]", " ", _fold_ascii(text))
    t = _E_NUMBER_SPACE.sub(r"e\1", t)
    for rx, replacement in _NON_ALLERGEN_SUBS:
        t = rx.sub(replacement, t)
    return t


# "Eser miktarda" (çapraz bulaşma) ifadeleri. Türkçede liste fiilden önce gelir
# ("eser miktarda fındık ve süt içerebilir"), diğer dillerde sonra ("may contain
# traces of nuts", "peut contenir", "kann Spuren von ... enthalten").
_TRACE_LEAD = re.compile(
    r"\b(?:eser|iz)\s+miktar\w*|\bmay\s+(?:also\s+)?contain|\b(?:can|might)\s+contain|"
    r"\btraces?\b|\bpeut\s+contenir|\bspuren\b|\bpuo\s+contenere|\btracce\b|"
    r"\bpuede\s+contener|\btrazas\b|\bsporen\b")
_TRACE_TAIL = re.compile(
    r"\bicerebilir\w*|\b(?:islendigi|uretildigi|kullanildigi)\s+(?:tesis|fabrika|hat)\w*|"
    r"\benthalten\b|\bbevatten\b")
_CLAUSE_BREAK = re.compile(r"(?<!\d)[.;:](?!\d)|\balerjen\w*")
_SENTENCE_END = re.compile(r"(?<!\d)[.;\n](?!\d)")
_MAX_UNMARKED_TRACE_CLAUSE = 150


def _trace_spans(t: str) -> List[Tuple[int, int]]:
    """Metindeki "içerebilir" cümleciklerinin [başlangıç, bitiş) aralıkları."""
    spans = []
    for m in _TRACE_TAIL.finditer(t):
        lo = max(0, m.start() - 400)
        window = t[lo:m.start()]
        brk = max((b.end() for b in _CLAUSE_BREAK.finditer(window)), default=0)
        leads = [x.start() for x in _TRACE_LEAD.finditer(window) if x.start() >= brk]
        clause = window[brk:]
        if leads:
            start = lo + leads[0]
        elif (len(clause) <= _MAX_UNMARKED_TRACE_CLAUSE
              and (brk > 0 or (len(clause) <= 60 and not re.search(r"[%(]", clause)))):
            # "Süt, soya ve fındık içerebilir." — cümle başından itibaren
            start = lo + brk
        else:
            continue    # uzun, işaretsiz cümle: içindekiler listesi olabilir, dokunma
        spans.append((start, m.end()))
    for m in _TRACE_LEAD.finditer(t):
        if any(a <= m.start() < b for a, b in spans):
            continue
        end = len(t)
        for rx in (_SENTENCE_END, _TRACE_TAIL):
            e = rx.search(t, m.end())
            if e:
                end = min(end, e.end())
        spans.append((m.start(), min(end, m.end() + 250)))
    return spans


def detect_allergens_detailed(text: str) -> Tuple[List[str], List[str]]:
    """(içerir, yalnızca eser miktarda içerebilir) alerjen listeleri.

    Bir alerjen, bütün geçişleri "eser miktarda ... içerebilir" türü bir
    cümlecik içindeyse "eser" sayılır; bir kez bile dışında geçerse "içerir".
    """
    t = _allergen_text(text)
    spans = _trace_spans(t)
    contains, traces = [], []
    for allergen, patterns in _ALLERGEN_PATTERNS:
        in_trace = in_body = False
        for rx, exclude_before in patterns:
            for m in rx.finditer(t):
                if (_NEGATION_AFTER.match(t, m.end())
                        or _NEGATION_BEFORE.search(t[max(0, m.start() - 20):m.start()])
                        or (exclude_before
                            and exclude_before.search(t[max(0, m.start() - 30):m.start()]))):
                    continue
                if any(a <= m.start() < b for a, b in spans):
                    in_trace = True
                else:
                    in_body = True
                    break
            if in_body:
                break
        if in_body:
            contains.append(allergen)
        elif in_trace:
            traces.append(allergen)
    return contains, traces


def detect_allergens(text: str) -> List[str]:
    """İçerik metninden alerjen tespiti (AB 1169/2011 ve TGK'daki 14 alerjen),
    eser miktar uyarıları dahil.

    Büyük harfli ve aksansız yazımları ("FINDIK", "farine de BLE") ve Türkçe
    ekleri ("inek sütü") tanır; "glutensiz", "sans gluten", "cocoa butter",
    "pirinç unu" alerjen sayılmaz. Yaygın Avrupa dillerindeki karşılıkları da tanır.
    """
    contains, traces = detect_allergens_detailed(text)
    return merge_allergens(contains, traces)


def split_ingredient_list(text: str) -> List[str]:
    """İçindekiler metnini üst düzey bileşenlere böler (uygulamada gösterim için).

    Yalnızca parantez dışındaki virgül ve noktalı virgüllerden bölünür; ondalık
    virgül ("%9,5") bölünmez. Parçalar ", " ile birleştirilince metin aynen
    (ayırıcıdan sonraki boşluklar dışında) geri gelir."""
    t = text or ""
    out, buf, depth = [], [], 0
    for i, ch in enumerate(t):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        elif ch in ",;" and depth == 0 and not (
                ch == "," and 0 < i < len(t) - 1 and t[i - 1].isdigit() and t[i + 1].isdigit()):
            part = "".join(buf).strip()
            if part:
                out.append(part)
            buf = []
            continue
        buf.append(ch)
    part = "".join(buf).strip()
    if part:
        out.append(part)
    return out


_GROUP_REF = re.compile(r"\\(\d)")


def _sub_mapped(rx, repl: str, t: str, spans: List[Tuple[int, int]]):
    """rx.sub(repl, t) ile aynı metni üretir; her karakterin orijinal metindeki
    [başlangıç, bitiş) aralığını da taşır. Gruptan gelen karakterler kendi
    yerini, sabit metin ise eşleşmenin tamamını gösterir."""
    pieces = _GROUP_REF.split(repl)
    out, out_spans, pos = [], [], 0
    for m in rx.finditer(t):
        if m.end() == m.start():
            continue
        out.append(t[pos:m.start()])
        out_spans.extend(spans[pos:m.start()])
        lo = min(s for s, _ in spans[m.start():m.end()])
        hi = max(e for _, e in spans[m.start():m.end()])
        for k, piece in enumerate(pieces):
            if k % 2 == 0:
                out.append(piece)
                out_spans.extend([(lo, hi)] * len(piece))
            elif m.group(int(piece)) is not None:
                g = int(piece)
                out.append(m.group(g))
                out_spans.extend(spans[m.start(g):m.end(g)])
        pos = m.end()
    out.append(t[pos:])
    out_spans.extend(spans[pos:])
    return "".join(out), out_spans


def _allergen_text_mapped(text: str):
    """_allergen_text ile aynı metin + her karakterin orijinal konumu."""
    chars, spans = [], []
    for i, ch in enumerate(text or ""):
        for c in _fold_ascii(ch):
            chars.append(c)
            spans.append((i, i + 1))
    t = re.sub(r"[_*]", " ", "".join(chars))
    t, spans = _sub_mapped(_E_NUMBER_SPACE, r"e\1", t, spans)
    for rx, replacement in _NON_ALLERGEN_SUBS:
        t, spans = _sub_mapped(rx, replacement, t, spans)
    return t, spans


def allergen_marks(text: str) -> List[List[int]]:
    """İçerik metninde alerjen geçen kelimelerin [başlangıç, bitiş) aralıkları
    (verilen metne göre), ambalajlardaki gibi kalın göstermek için.

    Alerjen tespitiyle aynı kalıplar kullanılır: yokluk bildiren kullanımlar
    ("glutensiz", "süt içermez") ve alerjen sayılmayanlar ("hindistan cevizi
    sütü", "pirinç unu") işaretlenmez. Eşleşme kelimenin tamamına genişletilir
    ("süttozu", "fındıklı")."""
    src = text or ""
    t, spans = _allergen_text_mapped(src)
    found = []
    for _allergen, patterns in _ALLERGEN_PATTERNS:
        for rx, exclude_before in patterns:
            for m in rx.finditer(t):
                if (m.end() == m.start()
                        or _NEGATION_AFTER.match(t, m.end())
                        or _NEGATION_BEFORE.search(t[max(0, m.start() - 20):m.start()])
                        or (exclude_before
                            and exclude_before.search(t[max(0, m.start() - 30):m.start()]))):
                    continue
                lo = min(s for s, _ in spans[m.start():m.end()])
                hi = max(e for _, e in spans[m.start():m.end()])
                while lo > 0 and src[lo - 1].isalnum():
                    lo -= 1
                while hi < len(src) and src[hi].isalnum():
                    hi += 1
                found.append((lo, hi))
    merged: List[List[int]] = []
    for lo, hi in sorted(found):
        if merged and lo <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return merged


# Open Food Facts allergens_tags / traces_tags → uygulama anahtarları
_OFF_ALLERGEN_TAGS = {
    "en:milk": "süt", "en:gluten": "gluten", "en:eggs": "yumurta",
    "en:soybeans": "soya", "en:nuts": "kuruyemiş", "en:peanuts": "kuruyemiş",
    "en:fish": "balık", "en:crustaceans": "kabuklu", "en:molluscs": "yumuşakça",
    "en:sesame-seeds": "susam", "en:mustard": "hardal", "en:celery": "kereviz",
    "en:sulphur-dioxide-and-sulphites": "sülfit", "en:lupin": "lupin",
}


def allergens_from_off_tags(tags) -> List[str]:
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",")]
    return [_OFF_ALLERGEN_TAGS[t] for t in (tags or []) if t in _OFF_ALLERGEN_TAGS]


def merge_allergens(*lists) -> List[str]:
    """Birden fazla kaynağın birleşimi, ALLERGENS sırasıyla."""
    seen = {a for lst in lists for a in (lst or [])}
    return [a for a in ALLERGENS if a in seen]


def allergen_info(text: str, off_product: Optional[dict] = None) -> Tuple[List[str], List[str]]:
    """(tüm alerjenler, yalnızca eser miktarda olanlar).

    Metin tespiti OFF'un kendi etiketleriyle birleştirilir; bir kaynak
    "içerir" diyorsa alerjen eser listesine düşürülmez."""
    contains, traces = detect_allergens_detailed(text)
    off = off_product or {}
    contains = merge_allergens(contains, allergens_from_off_tags(off.get("allergens_tags")))
    traces = [a for a in merge_allergens(traces, allergens_from_off_tags(off.get("traces_tags")))
              if a not in contains]
    return merge_allergens(contains, traces), traces


# ============================================================
# RİSK ANALİZİ (BUG 2 düzeltmesi — v3.0.0 şema)
# ============================================================
# Risk veritabanındaki sınıf adları tek bir maddeyi göstermez: "emülgatör" her
# emülgatör, "tatlandırıcı" her tatlandırıcıdır; E471 / aspartam diye
# gösterilmeleri yanlış olur. "karamel" çoğu zaman renklendirici değil
# lezzettir, "sirke" katkı maddesi (E260) değil gıdadır, "un" her undur.
_ADDITIVE_GENERIC_KEYWORDS = {
    "emulgator", "tatlandirici", "lezzet artirici", "seker alkolu", "karamel", "sirke", "un",
}
# Birden fazla maddeye ait olup yanlış olana bağlanmış keyword'ler
_ADDITIVE_DENY = {
    "E249": {"nitrit", "nitrite"},          # yalın "nitrit" = sodyum nitrit (E250)
    "E214": {"paraben"}, "E218": {"paraben"},
    "E339": {"sodyum difosfat"},            # difosfat = E450
    "E470a": {"sodyum aluminyum fosfat"},   # = E541
    "E1410": {"e1422"},                     # kendi kaydı var
    "E150": {"e150c", "e150d"},             # kendi kayıtları var
}
# Ek adlar (AB katkı maddesi adlarının yaygın dil karşılıkları); düz metin =
# kelime içinde arama, "re:" ile başlayan = düzenli ifade
_ADDITIVE_SYNONYMS = {
    "E150c": ["amonyak karamel"],
    "E150d": ["sulfit amonyak karamel", "sulfitli amonyak karamel", "amonyak sulfit karamel",
              "amonyum sulfit karamel", "sulphite ammonia caramel", "ammonia sulphite caramel",
              "ammonia sulfite caramel", "ammonium sulphite caramel", "ammonium sulfite caramel",
              "caramel au sulfite d'ammonium", "ammoniumsulfit-zuckerkulor"],
    "E150": ["karamel renklendirici", "renklendirici (karamel", "renklendirici: karamel",
             "caramel colo", "colour (caramel", "colour: caramel", "colouring (caramel",
             "colorant: caramel", "colorant (caramel", "colorant caramel", "zuckerkulor",
             "kostik sulfit karamel", "caustic sulphite caramel", "plain caramel",
             r"re:\bcaramel\s*\(\s*colou?r", "colours (caramel", "colours: caramel"],
    "E200": ["acide sorbique", "sorbinsaure"],
    "E220": ["sulphur dioxide", "anhydride sulfureux", "dioxyde de soufre", "schwefeldioxid"],
    "E221": ["sodium sulphite", "sulfite de sodium", "natriumsulfit"],
    "E223": ["sodium metabisulphite", "sodium disulphite", "sodium disulfite",
             "metabisulfite de sodium", "disulfite de sodium", "natriummetabisulfit",
             "natriumdisulfit", "metabisulfito de sodio", "metabisulfito sodico",
             "metabisolfito di sodio"],
    "E224": ["potassium metabisulphite", "potassium disulphite", "potassium disulfite",
             "metabisulfite de potassium", "disulfite de potassium", "kaliummetabisulfit",
             "kaliumdisulfit", "metabisulfito de potasio", "metabisolfito di potassio"],
    "E262": ["sodium diacetate", "diacetate de sodium", "natriumdiacetat"],
    "E202": ["sorbate de potassium", "kaliumsorbat", "sorbato di potassio", "sorbato de potasio"],
    "E211": ["benzoate de sodium", "natriumbenzoat", "benzoato di sodio", "benzoato de sodio"],
    "E250": ["nitrite de sodium", "natriumnitrit", "nitrito di sodio", "nitrito de sodio"],
    "E251": ["nitrate de sodium", "natriumnitrat"],
    "E252": ["nitrate de potassium", "kaliumnitrat"],
    "E270": ["acide lactique", "milchsaure", "acido lattico", "acido lactico"],
    "E296": ["acide malique", "apfelsaure", "acido malico"],
    "E300": ["acide ascorbique", "ascorbinsaure", "acido ascorbico"],
    "E301": ["ascorbate de sodium", "natriumascorbat"],
    "E322": ["lecitina", "lezithin"],
    "E330": ["acide citrique", "citronensaure", "acido citrico", "citroenzuur", "kwas cytrynowy"],
    "E331": ["citrate de sodium", "citrates de sodium", "natriumcitrat", "citrato de sodio",
             "citrato di sodio", "citrato sodico"],
    "E334": ["acide tartrique", "weinsaure"],
    "E338": ["acide phosphorique", "phosphorsaure"],
    "E407": ["carraghenane", "carragenina", "carrageen"],
    "E410": ["gomme de caroube", "johannisbrotkernmehl", "farine de graines de caroube",
             "carob bean gum", "keciboynuzu zamki"],
    "E412": ["gomme de guar", "gomme guar", "guarkernmehl", "goma guar"],
    "E414": ["gomme arabique", "gummi arabicum", "arap zamki", "akasya zamki"],
    "E415": ["gomme xanthane", "xanthan", "ksantan"],
    "E440": ["pectine"],
    "E450": ["diphosphate", "pyrophosphate"],
    "E466": ["cellulose gum", "carboxymethylcellulose", "karboksimetilseluloz"],
    "E471": [r"re:mono\W*(?:ve|and|et|und|e|y|&)?\W*di\W*gl[iy][sc]er[iy][dt]\w*"],
    "E472e": ["diasetil tartarik", "diacetyl tartaric", "diacetyltartrique",
              "diacetylweinsaure", "datem"],
    "E476": ["polyglycerol polyricinoleate", "poligliserol polirisinoleat", "polyricinoleate",
             "polirisinoleat", "polirisinolat"],
    "E500": ["sodyum hidrojen karbonat", "sodium hydrogen carbonate", "sodium bicarbonate",
             "bicarbonate de sodium", "carbonate de sodium", "carbonates de sodium",
             "hydrogenocarbonate de sodium", "natriumcarbonat", "natriumhydrogencarbonat",
             "baking soda"],
    "E503": ["amonyum hidrojen karbonat", "ammonium hydrogen carbonate", "ammonium bicarbonate",
             "carbonate d'ammonium", "carbonates d'ammonium", "hydrogenocarbonate d'ammonium",
             "ammoniumcarbonat", "ammoniumhydrogencarbonat"],
    "E621": ["monosodium glutamate", "sodium glutamate", "glutamate monosodique",
             "mononatriumglutamat", "glutammato monosodico", "glutamato monosodico"],
    "E627": ["disodium guanylate", "sodium guanylate", "guanylate disodique", "dinatriumguanylat"],
    "E631": ["disodium inosinate", "sodium inosinate", "inosinate disodique", "dinatriuminosinat"],
    "E950": ["acesulfame"],
}
# Katkı adı içeren ama o katkı olmayan ifadeler: eşleşmeyi bastırırlar
_ADDITIVE_BLOCKERS = (
    "maltodekstrin", "maltodextrin", "siklodekstrin", "cyclodextrin",
    r"re:t?h?iamin\w*\s+(?:mono)?nitrat\w*", "mononitrat",
    "poligliserol", "polyglycerol",
)
# "mono ve digliseridlerinin ... tartarik asit esterleri" / "citric acid esters of
# mono- and diglycerides" E471 değil, E472 ailesidir
_E471_NOT_BEFORE = re.compile(r"ester\w*\s+(?:\w+\s+)?(?:of|de|des|der|von|di|degli)\s+$")
_E471_NOT_AFTER = re.compile(r"[^,;]{0,60}ester")
_ADD_NEG_AFTER = re.compile(
    r"\s*-?\s*(?:s[iu]z\b|free\b|frei\b|icerme|bulunmaz|ilavesiz|eklenmemis|ilave edilmemis)")
_ADD_NEG_BEFORE = re.compile(
    r"\b(?:sans|sin|senza|ohne|without|no|free\s+from)(?:\s+added)?\s*[:\-]?\s*$")
_E_ROMAN = re.compile(r"\b(e\d{3,4}[a-f]?)\s*\(?(?:iii|ii|iv|i|v)\)?(?![a-z])")
_OFF_ADDITIVE_TAG = re.compile(r"^en:(e\d{3,4})([a-f]?)(?:iii|ii|iv|i|v)?$")
_additive_cache: Dict[int, tuple] = {}


def _additive_pattern(kw: str) -> "re.Pattern":
    if kw.startswith("re:"):
        return re.compile(kw[3:])
    if len(kw) <= 5:
        return re.compile(r"\b" + re.escape(kw) + r"\b")
    return re.compile(re.escape(kw))


def _compiled_additives(risk_scores: Dict[str, dict]) -> tuple:
    cache_key = id(risk_scores)
    cached = _additive_cache.get(cache_key)
    if cached is not None and cached[0] is risk_scores:
        return cached[1]
    entries = []
    for key, info in risk_scores.items():
        if not isinstance(info, dict):
            continue
        deny = _ADDITIVE_GENERIC_KEYWORDS | _ADDITIVE_DENY.get(key, set())
        kws = [_fold_ascii(k) for k in list(info.get("keywords", [])) + [key]]
        kws += [k if k.startswith("re:") else _fold_ascii(k)
                for k in _ADDITIVE_SYNONYMS.get(key, [])]
        patterns = [_additive_pattern(k) for k in dict.fromkeys(kws) if k and k not in deny]
        entries.append((key, info, patterns))
    blockers = [_additive_pattern(b if b.startswith("re:") else _fold_ascii(b))
                for b in _ADDITIVE_BLOCKERS]
    index = {k.lower(): k for k in risk_scores if isinstance(risk_scores[k], dict)}
    compiled = (entries, blockers, index)
    if len(_additive_cache) > 4:
        _additive_cache.clear()
    _additive_cache[cache_key] = (risk_scores, compiled)
    return compiled


def _additive_keys_from_tags(tags, index: Dict[str, str]) -> List[str]:
    """OFF additives_tags ("en:e322i", "en:e150d") → risk veritabanı anahtarları."""
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",")]
    keys = []
    for t in tags or []:
        m = _OFF_ADDITIVE_TAG.match((t or "").strip().lower())
        if not m:
            continue
        key = index.get(m.group(1) + m.group(2)) or index.get(m.group(1))
        if key and key not in keys:
            keys.append(key)
    return keys


def _risk_item(key: str, info: dict) -> dict:
    return {
        # Geriye uyumlu alanlar (Flutter'a dokunmaz)
        "name": info.get("name", key),
        "name_en": info.get("name_en", ""),  # İngilizce UI için
        "ewg_score": info.get("ewg_score", 1),
        "risk": info.get("risk", ""),
        "risk_en": info.get("risk_en", ""),  # İngilizce UI açıklaması
        # v3.0.0 — kanıt-etiketli model
        "evidence": info.get("evidence", "limited"),
        "color": info.get("color", "yellow"),
        "source": info.get("source_detail", ""),
        "source_en": info.get("source_en", ""),  # İngilizce kaynak metni
        "code": key,
    }


def analyze_ingredients(text: str, risk_scores: Dict[str, dict],
                        additives_tags=None) -> Tuple[List[Dict], int]:
    """İçerik metnindeki riskli katkı maddeleri ve içerikler (v3.0.0 şema).

    Her bileşen parçasında tüm maddeler aranır; iç içe eşleşmede en uzun
    (en belirgin) ad kazanır: "sodyum metabisülfit" E223'tür, ayrıca E220
    sayılmaz. Open Food Facts'in çıkardığı additives_tags varsa eklenir.
    """
    entries, blockers, index = _compiled_additives(risk_scores)
    t = re.sub(r"\be[\s\-]+(\d{3,4}[a-f]?)\b", r"e\1", _fold_ascii(text or ""))
    t = _E_ROMAN.sub(r"\1", t)

    # "Eser miktarda kükürt dioksit içerebilir" katkı maddesi değil, bulaşma uyarısı
    trace_spans = _trace_spans(t)
    hits = []   # (uzunluk, başlangıç, bitiş, sıra, key)  — key None = engelleyici
    for order, (key, info, patterns) in enumerate(entries):
        for rx in patterns:
            for m in rx.finditer(t):
                s, e = m.start(), m.end()
                if _ADD_NEG_AFTER.match(t, e) or _ADD_NEG_BEFORE.search(t[max(0, s - 20):s]):
                    continue
                if any(a <= s < b for a, b in trace_spans):
                    continue
                if key == "E471" and (_E471_NOT_BEFORE.search(t[max(0, s - 40):s])
                                      or (m.group(0).endswith("in")   # "-lerinin" (tamlama)
                                          and _E471_NOT_AFTER.match(t, e))):
                    continue
                hits.append((e - s, s, e, order, key))
    for rx in blockers:
        for m in rx.finditer(t):
            hits.append((m.end() - m.start(), m.start(), m.end(), -1, None))

    accepted, found_keys = [], []
    for length, s, e, order, key in sorted(hits, key=lambda h: (-h[0], h[3], h[1])):
        if any(a <= s and e <= b and k != key for a, b, k in accepted):
            continue        # daha uzun başka bir adın parçası
        accepted.append((s, e, key))
        if key is not None and key not in found_keys:
            found_keys.append(key)
    # Metindeki sıraya göre
    first_pos = {}
    for s, e, key in accepted:
        if key is not None:
            first_pos[key] = min(first_pos.get(key, s), s)
    found_keys.sort(key=lambda k: first_pos[k])
    for key in _additive_keys_from_tags(additives_tags, index):
        if key not in found_keys:
            found_keys.append(key)

    risks, seen = [], set()
    for key in found_keys:
        item = _risk_item(key, risk_scores[key])
        if item["name"] not in seen:
            seen.add(item["name"])
            risks.append(item)
    max_ewg = max((r["ewg_score"] for r in risks), default=0)
    return risks, max_ewg


def _tr_norm(s: str) -> str:
    """Tam Türkçe normalize: ığüşöç → igusoc (arama terimi için).

    fold_i önce gelir: "İçim".lower() → "i̇çim" (birleşik nokta) olduğu için
    büyük İ ile yazılan aramalar veritabanındaki "icim" ile hiç eşleşmiyordu.
    """
    s = fold_i(s)
    table = str.maketrans("ğüşöçî", "gusoci")
    return s.translate(table)
