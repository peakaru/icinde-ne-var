"""
İçinde Ne Var? - Backend API (Hugging Face Spaces)
SQLite veritabanı + Open Food Facts API hibrit kullanım.

Version: 2.0.0 — Düzeltmeler:
  - Sodium birim normalization (BUG 1)
  - risk_scores.json v3.0.0 şema desteği (BUG 2)
  - İçecek kategorisi isim-bazlı tespit (BUG 4)
  - Resmi Nutri-Score eşik tabloları + protein kuralı (BUG 5, 6)
  - OFF sadece yerel veri eksikse çağrılıyor (SORUN 8)
  - image_url düzeltildi (SORUN 9)
  - Keyword false-positive azaltıldı (SORUN 7)

Kanal uyumluluğu: Eski JSON alanları (name, ewg_score, risk) korundu,
yeni alanlar (evidence, color, source_detail) eklendi. Flutter'a dokunmadan
çalışır; istersen yeni alanları UI'da gösterirsin.
"""
import json
import time
import os
import re
import duckdb  # SQLite yerine (parquet + columnar)
from typing import Optional, Tuple, List, Dict
from fastapi import FastAPI, HTTPException, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import io
import httpx
from analysis import (
    ProductFeatures,
    analyze_ingredients,
    calculate_nutri_score_2024,
    detect_allergens,
    fvln_tahmin,
    is_beverage,
    normalize_sodium_mg,
    _tr_norm,
)
# HF ZeroGPU için zorunlu — GPU function bekliyor
try:
    import spaces  # noqa: F401
    _SPACES_AVAILABLE = True
except ImportError:
    _SPACES_AVAILABLE = False

# Barkod okuma (opsiyonel — telefonda yapılıyor, backend'de gerek değil)
try:
    from pyzbar.pyzbar import decode as pyzbar_decode
    PYZBAR_AVAILABLE = True
except Exception:
    PYZBAR_AVAILABLE = False
    pyzbar_decode = None
    print("[UYARI] pyzbar yüklenemedi — /analyze-image devre dışı (telefonda barkod okuma yapılır)")

app = FastAPI(title="İçinde Ne Var API", version="3.1.0")


# ZeroGPU dummy function — HF ZeroGPU Space bir @spaces.GPU decorator bekliyor.
# Backend GPU kullanmaz ama bu decorator olmadan Space başlamıyor.
if _SPACES_AVAILABLE:
    @spaces.GPU
    def _zero_gpu_placeholder():
        """ZeroGPU başlatma için dummy (GPU kullanılmıyor)."""
        return None
    _zero_gpu_placeholder()

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================
# RATE LIMITING — IP başına 30 istek/dk (basit, bağımlılıksız)
# HF proxy arkasında olduğu için gerçek IP X-Forwarded-For'dan okunur.
# Memory'de tutulur; Space restart'ta sıfırlanır (kabul edilebilir).
# ============================================================
from collections import defaultdict as _dd
from fastapi.responses import JSONResponse as _JSONResponse

_RATE_LIMIT = 30      # istek sayısı
_RATE_WINDOW = 60.0   # pencere (saniye)
_rate_map: dict = _dd(list)
_rate_exempt_paths = {"/", "/health"}  # health ping'leri (cron-job) limit dışı

# Global günlük çekirdek sınırı: bulk kazımayı (API'den tüm DB'yi tarama)
# ekonomik olarak anlamsızlaştırır. Meşru trafik bunun çok altında.
_DAILY_CORE_LIMIT = 200_000
_daily_core = {"day": None, "count": 0}
_off_map: dict = _dd(list)  # IP → OFF fallback çağrı zamanları


def client_ip(request) -> str:
    """İsteği yapan gerçek IP.

    HF proxy'si gerçek istemci IP'sini X-Forwarded-For'un SONUNA ekler;
    istemcinin kendi gönderdiği değerler başta kalır ("sahte, gerçek").
    İlk değeri okumak, her istekte başlığı değiştiren birinin rate limit'i
    tamamen atlatmasına izin veriyordu — bu yüzden en sağdaki değer alınır.
    """
    xff = [p.strip() for p in request.headers.get("x-forwarded-for", "").split(",") if p.strip()]
    if xff:
        return xff[-1]
    return request.client.host if request.client else "unknown"


@app.middleware("http")
async def rate_limit_middleware(request, call_next):
    path = request.url.path
    if path not in _rate_exempt_paths:
        ip = client_ip(request)
        now = time.time()
        # Pencere dışı kayıtları temizle
        _rate_map[ip] = [t for t in _rate_map[ip] if now - t < _RATE_WINDOW]
        if len(_rate_map[ip]) >= _RATE_LIMIT:
            return _JSONResponse(
                status_code=429,
                content={"detail": "Çok fazla istek. Lütfen bir dakika içinde tekrar deneyin."},
            )
        _rate_map[ip].append(now)
        # Boyutu sınırla (memory koruması — maksimum 10K IP takip et).
        # Önce süresi dolmuş IP'ler atılır; hepsini silmek aktif limitleri de sıfırlardı.
        if len(_rate_map) > 10000:
            for k in [k for k, v in _rate_map.items() if not v or now - v[-1] >= _RATE_WINDOW]:
                del _rate_map[k]
            if len(_rate_map) > 10000:
                _rate_map.clear()
        # Global günlük çekirdek sınırı (veri kazıma koruması)
        today = time.strftime("%Y-%m-%d")
        if _daily_core["day"] != today:
            _daily_core["day"] = today
            _daily_core["count"] = 0
        _daily_core["count"] += 1
        if _daily_core["count"] > _DAILY_CORE_LIMIT:
            return _JSONResponse(
                status_code=429,
                content={"detail": "Günlük servis limiti aşıldı."},
            )
    response = await call_next(request)
    # Güvenlik başlıkları (Gradio embed ile uyumlu — frame kısıtı yok)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Permitted-Cross-Domain-Policies"] = "none"
    return response

# Veritabanı: DuckDB + Parquet (aşağıda get_db() içinde tanımlı)
# Eski SQLite (products.db) artık kullanılmıyor — Parquet 4.7x daha küçük

# Risk skorlarını yükle (v3.0.0 şema — evidence/color/source ile)
RISK_SCORES_PATH = "risk_scores.json"
try:
    with open(RISK_SCORES_PATH, "r", encoding="utf-8") as f:
        _risk_raw = json.load(f)
    # _meta anahtarını ayıkla
    risk_scores = {k: v for k, v in _risk_raw.items() if k != "_meta"}
    print(f"[INFO] {len(risk_scores)} risk maddesi yüklendi")
except Exception as e:
    print(f"[HATA] risk_scores.json yüklenemedi: {e}")
    risk_scores = {}

# ============================================================
# PORSİYON / GRAMAJ ÇIKARIMI
# ============================================================
# Birim dönüşüm tablosu — hepsini gram (g) veya mL'yi gram kabul eder
# (besin değerleri 100g başına, hacim→ağırlık kabulu yoğunluk ~1.0)
UNIT_TO_GRAMS = {
    "kg": 1000.0,
    "gr": 1.0, "g": 1.0,
    "mg": 0.001,
    "lt": 1000.0, "l": 1000.0,
    "ml": 1.0, "cc": 1.0,
    "cl": 10.0,
    "oz": 28.35,
    "lb": 453.6,
}

# product_name'den gramaj çıkar:
#   "Eti Cin 325 G" → 325 g
#   "Coca Cola 1.5 L" → 1500 ml
#   "Tahin 550 G (Bidon)" → 550 g
#   "Su 6x200 ml" → 200 ml (porsiyon), paket için 6*200=1200
#   "Yoğurt 1 KG" → 1000 g
_QUANTITY_RE = re.compile(
    r'(\d+(?:[.,]\d+)?)\s*(kg|gr|g|mg|lt|l|ml|cc|cl|oz|lb)\b',
    re.IGNORECASE,
)
# Çoklu paket: "6x200 ml", "2x100 g", "4x1 L"
_MULTI_RE = re.compile(r'(\d+)\s*[xX×]\s*(\d+(?:[.,]\d+)?)\s*(kg|gr|g|mg|lt|l|ml|cc|cl|oz|lb)\b', re.IGNORECASE)

# Ham birim → normalize edilmiş UI birimi ("g" veya "ml" tabanlı)
_UNIT_NORMALIZE = {
    "kg": "kg", "gr": "g", "g": "g", "mg": "mg",
    "lt": "l", "l": "l", "ml": "ml", "cc": "ml", "cl": "cl",
}


def _is_volume_unit(unit: str) -> bool:
    """Birim hacim mi (ml/l) kontrol et."""
    return unit in ("ml", "l", "lt", "cc")


def extract_quantity_from_name(product_name: str) -> Tuple[float, float, str, str]:
    """
    product_name'den paket ve porsiyon miktarını çıkar.

    Returns:
        (product_quantity, serving_quantity, raw_text, unit)
        quantity değerleri birimin doğal ölçeğinde döner:
          - "325 G"  → (325, 0, "325 G", "g")
          - "1.5 L"  → (1.5, 0, "1.5 L", "l")   ← 1500 değil!
          - "330 ml" → (330, 0, "330 ml", "ml")
          - "6x200 ml" → (1200, 200, "6x200 ml", "ml")
        Bulunamazsa (0.0, 0.0, "", "")
    """
    if not product_name:
        return 0.0, 0.0, "", ""

    # 1. Önce çoklu paket deseni: "6x200 ml" → porsiyon=200, paket=1200
    m_multi = _MULTI_RE.search(product_name)
    if m_multi:
        count = float(m_multi.group(1).replace(',', '.'))
        unit_val = float(m_multi.group(2).replace(',', '.'))
        unit_raw = m_multi.group(3).lower()
        unit = _UNIT_NORMALIZE.get(unit_raw, "g")
        # Hacim biriminde: değer birimin doğal ölçeğinde kalır
        # (ml: sayı direkt ml; l: sayı litre)
        if unit in ("ml", "l"):
            per_unit = unit_val
            total = count * per_unit
        else:
            # Ağırlık: kg/gr farkını scala (g tabanına)
            multiplier = UNIT_TO_GRAMS.get(unit_raw, 1.0)
            per_unit = unit_val * multiplier
            total = count * per_unit
        return total, per_unit, m_multi.group(0), unit

    # 2. Tek miktar: "325 G", "1.5 L", "330 ml"
    m = _QUANTITY_RE.search(product_name)
    if m:
        unit_val = float(m.group(1).replace(',', '.'))
        unit_raw = m.group(2).lower()
        unit = _UNIT_NORMALIZE.get(unit_raw, "g")
        if unit in ("ml", "l"):
            # Hacim: doğal ölçekte bırak ("1.5 L" → 1.5, "330 ml" → 330)
            qty = unit_val
        else:
            multiplier = UNIT_TO_GRAMS.get(unit_raw, 1.0)
            qty = unit_val * multiplier
        return qty, 0.0, m.group(0), unit

    return 0.0, 0.0, "", ""


# ============================================================
# VERİTABANI & OFF
# ============================================================
# DuckDB + Parquet (SQLite yerine): 780 MB → 166 MB (4.7x kazanç)
# Parquet dosyası external okunur, DuckDB cache'li metadata ile hızlı sorgu.
PARQUET_PATH = "products.parquet"
_duck_conn = None  # global connection (lazy init)


DATA_REPO = "peakaru/icinde-ne-var-data"   # Parquet'in yaşadığı dataset reposu


def _resolve_parquet():
    """Parquet yolunu bul: önce lokal (geliştirme), yoksa HF dataset'ten indir.
    Space repo'sunda parquet tutulmadığı için (1 GB storage limiti) veri
    ayrı bir dataset reposunda yaşar ve ilk açılışta indirilir."""
    if os.path.exists(PARQUET_PATH):
        return PARQUET_PATH
    try:
        from huggingface_hub import hf_hub_download
        path = hf_hub_download(
            repo_id=DATA_REPO, repo_type="dataset",
            filename="products.parquet",
            # Dataset PRIVATE: erişim Space secret'taki HF_TOKEN ile
            token=os.environ.get("HF_TOKEN"),
        )
        print(f"[INFO] Parquet dataset'ten indirildi: {path}")
        return path
    except Exception as e:
        print(f"[HATA] Parquet indirilemedi: {e}")
        return None


def get_db():
    """Global DuckDB connection döndür (parquet'i view olarak yükler)."""
    global _duck_conn
    if _duck_conn is None:
        pq = _resolve_parquet()
        if pq:
            try:
                _duck_conn = duckdb.connect(database=":memory:", read_only=False)
                # Parquet'i view olarak yükle (lazy, hızlı başlangıç)
                _duck_conn.execute(
                    f"CREATE VIEW products AS SELECT * FROM read_parquet('{pq}')"
                )
                print(f"[INFO] Parquet yüklendi: {pq}")
            except Exception as e:
                print(f"[HATA] DuckDB başlatma: {e}")
                _duck_conn = None
    return _duck_conn


def get_product_from_db(barcode: str):
    conn = get_db()
    if not conn:
        return None
    try:
        result = conn.execute(
            "SELECT * FROM products WHERE code = ?", [barcode]
        ).fetchone()
        if result:
            # Kolon adlarını al
            cols = [d[0] for d in conn.description]
            return dict(zip(cols, result))
    except Exception as e:
        print(f"DB hatası: {e}")
    return None


async def get_product_from_off(barcode: str, caller_ip: str = "unknown"):
    """Open Food Facts API'den ürün bilgisi al.
    IP başına dakikada 10 OFF araması: rastgele barkod yağdıran kazıyıcılar
    bu API'yi bedava OFF proxy'si olarak kullanamaz; meşru kullanıcı için bol."""
    now = time.time()
    _off_map[caller_ip] = [t for t in _off_map[caller_ip] if now - t < 60.0]
    if len(_off_map[caller_ip]) >= 10:
        return None
    _off_map[caller_ip].append(now)
    url = f"https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if data.get("status") == 1:
                    return data.get("product", {})
    except Exception as e:
        print(f"OFF API hatası: {e}")
    return None


# ============================================================
# İSİMLE ARAMA — DuckDB (Türkçe-aware, isim + marka, kelime bazlı)
# ============================================================
@app.get("/search")
def search_products(q: str, limit: int = 10):
    """Ürün adı VEYA markasına göre ara. Barkod bilinmediğinde kullanılır.

    "ulker gofret" → her kelime isimde VEYA markada geçen ürünler (AND).
    "torku helva"  → torku (marka) + helva (isim) eşleşir.

    Query params:
      q: arama terimi (min 2 karakter)
      limit: max sonuç (default 10, max 25)
    """
    q = (q or "").strip()
    if len(q) < 2:
        raise HTTPException(status_code=400, detail="Arama terimi en az 2 karakter olmalı")
    if len(q) > 80:
        raise HTTPException(status_code=400, detail="Arama terimi çok uzun (max 80)")
    limit = max(1, min(limit, 25))

    conn = get_db()
    if not conn:
        raise HTTPException(status_code=500, detail="Veritabanı hazır değil")

    try:
        # Terimi kelimelere böl (max 4), her birini normalize et
        words = [_tr_norm(w) for w in q.split() if len(w) >= 2][:4]
        if not words:
            raise HTTPException(status_code=400, detail="Geçerli arama terimi girin")

        # Dinamik SQL: her kelime (isim LIKE ? OR marka LIKE ?), kelimeler AND
        # translate() ile DB tarafında da Türkçe normalize (ığüşöç → igusoc)
        NORM = "translate(lower(coalesce(%s, '')), 'ığüşöçİî', 'igusoci')"
        name_norm = NORM % "product_name"
        brand_norm = NORM % "brands"

        conds = []
        params = []
        for w in words:
            esc = w.replace("%", "\\%").replace("_", "\\_")
            pat = f"%{esc}%"
            conds.append(f"({name_norm} LIKE ? OR {brand_norm} LIKE ?)")
            params.extend([pat, pat])

        where = " AND ".join(conds)

        # Veri kalitesi: önce içeriği/besin verisi olan ürünler.
        # Nutri-Score'u ve içindekileri bilmediğimiz ürün arama sonucu olarak
        # kullanıcıyı boş detay ekranına düşürür — en sonda dursunlar.
        # (Parquet'te grade yok, backendde hesaplanır; varlığı energy'den anlaşılır)
        data_cond = ("(coalesce(ingredients_text, '') != '' "
                     "OR \"energy-kcal_100g\" IS NOT NULL)")

        def _run(extra: str):
            # Aynı barkod birden çok satırdaysa en zengini (içerik metni en uzun)
            # gelsin; sonuç listesinde aynı ürün iki kez çıkmasın.
            # Nutriment kolonları da taşınır → sonuçta NS grade gösterilir.
            return conn.execute(
                f"""
                SELECT code, product_name, brands, ingredients_text,
                       "energy-kcal_100g", "sugars_100g", "saturated-fat_100g",
                       "sodium_100g", "proteins_100g", "fiber_100g"
                FROM (
                  SELECT code, product_name, brands, ingredients_text,
                         "energy-kcal_100g", "sugars_100g", "saturated-fat_100g",
                         "sodium_100g", "proteins_100g", "fiber_100g",
                         row_number() OVER (
                           PARTITION BY code
                           ORDER BY length(coalesce(ingredients_text, '')) DESC,
                                    length(coalesce(product_name, '')) ASC
                         ) AS rn
                  FROM products
                  WHERE ({where}) AND code IS NOT NULL AND code != '' {extra}
                ) t
                WHERE rn = 1
                ORDER BY
                  CASE WHEN {name_norm} LIKE ? THEN 0 ELSE 1 END,
                  CASE WHEN coalesce(ingredients_text, '') != '' THEN 0 ELSE 1 END,
                  length(coalesce(product_name, ''))
                LIMIT ?
                """,
                params + [f"{words[0]}%", limit],
            ).fetchall()

        def _grade_for(name, en, sg, sf, na, pr, fb):
            # Enerjisi olmayan ürünün NS'i hesaplanamaz
            if not en:
                return None
            try:
                na_mg = normalize_sodium_mg(na)
                # Fiziksel olarak imkansız değerleri hesaba katma
                # (25000mg: gerçek tuzlular — soya sosu ~9600, Vegeta ~22400 — görünmeli)
                if na_mg and na_mg > 25000:
                    na_mg = 0.0
                f = ProductFeatures(
                    energy_100g=float(en or 0),
                    sugars_100g=float(sg or 0),
                    saturated_fat_100g=float(sf or 0),
                    sodium_100g=na_mg,
                    proteins_100g=float(pr or 0),
                    fiber_100g=float(fb or 0),
                )
                g, _, _ = calculate_nutri_score_2024(f, product_name=name or "")
                return g
            except Exception:
                return None

        # 1) Sadece verisi olan ürünler; 2) hiç yoksa filtresiz fallback
        rows = _run(f" AND {data_cond}")
        if not rows:
            rows = _run("")

        results = [
            {
                "barcode": code,
                "product_name": name or "",
                "brand": brands or "",
                "nutriscore": _grade_for(name, en, sg, sf, na, pr, fb),
            }
            for code, name, brands, _ing, en, sg, sf, na, pr, fb in rows
        ]

        # Benzer-ürün tekilleştirme: OFF'ta aynı ürün farklı ülkelerden
        # çok kez girilir ("Lipton ice tea" x8, her biri farklı NS ile).
        # İsim+marka çok benzer kayıtlar gizlenir; zengin verili olan
        # (sıralamada üstte) kalır.
        from difflib import SequenceMatcher
        seen_labels = []
        deduped = []
        for r in results:
            label = _tr_norm(f'{r["product_name"]} {r["brand"]}'.strip())
            if any(SequenceMatcher(None, label, s).ratio() > 0.82 for s in seen_labels):
                continue
            seen_labels.append(label)
            deduped.append(r)
        results = deduped

        return {"query": q, "count": len(results), "results": results}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Arama hatası: {e}")
        raise HTTPException(status_code=500, detail="Arama sırasında hata oluştu")


# ============================================================
# ENDPOINT'LER
# ============================================================
@app.get("/")
def root():
    return {"message": "İçinde Ne Var? API", "status": "running", "version": "3.1.0"}


@app.get("/legal", include_in_schema=False)
def legal():
    """Gizlilik politikası web sayfası (Play Console URL gereksinimi için)."""
    from fastapi.responses import FileResponse
    from pathlib import Path as _P
    f = _P(__file__).parent / "docs" / "index.html"
    if f.exists():
        return FileResponse(f, media_type="text/html")
    return HTMLResponse("<h1>İçinde Ne Var?</h1><p>Legal page missing</p>")


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/benchmark")
def benchmark():
    """ML benchmark verileri (eski API uyumluluğu)."""
    return [
        {"name": "Random Forest", "accuracy": 0.89, "precision": 0.88, "recall": 0.87, "f1_score": 0.87},
        {"name": "Gradient Boosting", "accuracy": 0.87, "precision": 0.86, "recall": 0.85, "f1_score": 0.85},
        {"name": "SVM", "accuracy": 0.82, "precision": 0.81, "recall": 0.80, "f1_score": 0.80},
        {"name": "Naive Bayes", "accuracy": 0.76, "precision": 0.75, "recall": 0.74, "f1_score": 0.74},
    ]


@app.get("/pending-barcodes")
def pending_barcodes(token: str = ""):
    """Bulunamayan barkodları listele ve dosyayı temizle (barkod kazandırma
    döngüsü — biz periyodik çekip DB'ye kazandırıyoruz). Basit token korumalı."""
    if token != os.environ.get("PENDING_TOKEN"):
        # Token yalnızca Space secret'tan gelir — kodda varsayılan değer YOK
        raise HTTPException(status_code=403, detail="Yetkisiz")
    codes = []
    try:
        with open("pending_barcodes.jsonl", encoding="utf-8") as f:
            codes = [line.strip() for line in f if line.strip()]
        os.remove("pending_barcodes.jsonl")
    except FileNotFoundError:
        pass
    return {"count": len(codes), "codes": codes}


@app.get("/barcode/{code}")
async def lookup_barcode(code: str, request: Request = None):
    code = (code or "").strip()
    # OFF fallback limiti için çağıran IP
    caller_ip = client_ip(request) if request is not None else "unknown"
    # Girdi doğrulama: sadece 8-14 hane rakam — çöp istekler OFF'ya iletilmez
    if not code.isdigit() or not (8 <= len(code) <= 14):
        raise HTTPException(status_code=400, detail="Geçersiz barkod formatı")
    # 1. Önce yerel veritabanından ara
    local_product = get_product_from_db(code)

    # 2. SORUN 8: OFF sadece yerel veri eksikse çağrılır
    off_product = None
    if not local_product or not local_product.get("ingredients_text"):
        off_product = await get_product_from_off(code, caller_ip)
    elif local_product:
        # Yerelde besin değeri eksikse OFF'tan tamamla
        if not local_product.get("energy-kcal_100g"):
            off_product = await get_product_from_off(code, caller_ip)

    # Veri kaynağını belirle
    if local_product and off_product:
        source = "Local + OFF"
    elif local_product:
        source = "Local Database"
    elif off_product:
        source = "Open Food Facts"
    else:
        # Bulunamayan barkodu kaydet — "barkod kazandırma döngüsü":
        # periyodik çekip barkod→isim→LOC eşleştirmeyle DB'ye kazandıracağız.
        try:
            import json as _json
            with open("pending_barcodes.jsonl", "a", encoding="utf-8") as _f:
                _f.write(_json.dumps({"code": code, "ts": time.time()}) + "\n")
        except Exception:
            pass
        raise HTTPException(status_code=404, detail="Ürün bulunamadı")

    # Ürün bilgilerini çıkar
    name = ""
    brand = ""
    ingredients = ""
    image_url = ""

    if local_product:
        name = local_product.get("product_name") or "Bilinmeyen Ürün"
        brand = local_product.get("brands") or ""
        ingredients = local_product.get("ingredients_text") or ""
    if off_product:
        if not name or name == "Bilinmeyen Ürün":
            name = off_product.get("product_name", off_product.get("product_name_tr", "Bilinmeyen Ürün"))
        if not brand:
            brand = off_product.get("brands", "")
        if not ingredients:
            ingredients = off_product.get("ingredients_text", off_product.get("ingredients_text_tr", ""))
        image_url = off_product.get("image_url", "")

    # Besin değerleri — öncelik sırası: OFF (zengin) > Local
    energy_kcal = 0.0
    sugars = 0.0
    sat_fat = 0.0
    sodium_raw = 0.0
    proteins = 0.0
    fiber = 0.0

    if off_product:
        nutrients = off_product.get("nutriments", {})
        energy_kcal = nutrients.get("energy-kcal_100g", 0) or 0
        if not energy_kcal and nutrients.get("energy_100g"):
            energy_kcal = nutrients.get("energy_100g", 0) / 4.184
        sugars = nutrients.get("sugars_100g", 0) or 0
        sat_fat = nutrients.get("saturated-fat_100g", 0) or 0
        sodium_raw = nutrients.get("sodium_100g", 0) or 0
        proteins = nutrients.get("proteins_100g", 0) or 0
        fiber = nutrients.get("fiber_100g", 0) or 0

    # Yerel veriyi OFF'tan eksik alanları doldur
    if local_product:
        if not energy_kcal and local_product.get("energy-kcal_100g"):
            energy_kcal = local_product["energy-kcal_100g"]
        if not sugars and local_product.get("sugars_100g"):
            sugars = local_product["sugars_100g"]
        if not sat_fat and local_product.get("saturated-fat_100g"):
            sat_fat = local_product["saturated-fat_100g"]
        if not sodium_raw and local_product.get("sodium_100g"):
            sodium_raw = local_product["sodium_100g"]
        if not proteins and local_product.get("proteins_100g"):
            proteins = local_product["proteins_100g"]
        if not fiber and local_product.get("fiber_100g"):
            fiber = local_product["fiber_100g"]

    # Sodium birim normalization (BUG 1 düzeltmesi)
    sodium_mg = normalize_sodium_mg(sodium_raw)

    # Fiziksel limit doğrulaması — OFF kullanıcı girişi hatalarını ele
    # (örn. içecekte 1960 mg/100g sodyum: deniz suyu ~1100 mg; tek hatalı
    # alan tüm Nutri-Score'u berbat etmesin → imkansız değer hesaba katılmaz)
    NUTRI_LIMITS = {
        "energy": 900.0, "sugars": 100.0, "sat_fat": 100.0,
        "sodium": 25000.0, "proteins": 90.0, "fiber": 80.0,
    }
    def _sane(val, key):
        try:
            v = float(val)
        except (TypeError, ValueError):
            return 0.0
        if v < 0 or v > NUTRI_LIMITS[key]:
            return 0.0
        return v

    energy_kcal = _sane(energy_kcal, "energy")
    sugars = _sane(sugars, "sugars")
    sat_fat = _sane(sat_fat, "sat_fat")
    sodium_mg = _sane(sodium_mg, "sodium")
    proteins = _sane(proteins, "proteins")
    fiber = _sane(fiber, "fiber")

    features = ProductFeatures(
        energy_100g=energy_kcal,
        sugars_100g=sugars,
        saturated_fat_100g=sat_fat,
        sodium_100g=sodium_mg,
        proteins_100g=proteins,
        fiber_100g=fiber,
    )

    # ============================================================
    # PORSİYON / PAKET MİKTARI ÇIKARIMI
    # ============================================================
    # Öncelik: OFF (yapılandırılmış) > product_name regex (fallback)
    product_quantity = 0.0   # toplam paket (g veya ml — birime göre)
    serving_quantity = 0.0   # 1 porsiyon
    serving_size_text = ""   # ham text ("1 kase (40g)", "1 can (330 ml)")
    quantity_source = "unknown"
    quantity_unit = "g"      # UI toggle için: "g" veya "ml"

    beverage = is_beverage(name)

    if off_product:
        try:
            pq = off_product.get("product_quantity") or 0
            product_quantity = float(pq) if pq else 0.0
        except (TypeError, ValueError):
            product_quantity = 0.0
        try:
            sq = off_product.get("serving_quantity") or 0
            serving_quantity = float(sq) if sq else 0.0
        except (TypeError, ValueError):
            serving_quantity = 0.0
        serving_size_text = off_product.get("serving_size", "") or ""
        if product_quantity > 0 or serving_quantity > 0:
            quantity_source = "off"
            # OFF grama yakın değer verir; içeceksen ml olarak yorumla
            if beverage:
                quantity_unit = "ml"
            # Ürün adı içecek belirtmese bile OFF'un serving metni "ml"
            # içeriyorsa hacim birimi kullan ("1 can (330 ml)" gibi)
            elif "ml" in serving_size_text.lower():
                quantity_unit = "ml"
            else:
                # OFF'un kendi birim alanı ya da ürün adındaki "ml",
                # içecek olmayan sıvılar için (krema, sos, yağ) hacim demektir
                pqu = (off_product.get("product_quantity_unit") or "").lower()
                if pqu in ("ml", "l", "lt", "cl", "cc") or re.search(r"\d\s*ml\b", (name or "").lower()):
                    quantity_unit = "ml"

    # OFF'ta yoksa product_name'den regex ile çıkarma dene
    if product_quantity == 0 and serving_quantity == 0 and name:
        regex_pkg, regex_srv, regex_text, regex_unit = extract_quantity_from_name(name)
        if regex_pkg > 0:
            # "l" birimi geldiğinde değer litre cinsinden → ml'e çevir (1.5 L → 1500 ml)
            if regex_unit == "l":
                regex_pkg *= 1000.0
                regex_srv *= 1000.0
            product_quantity = regex_pkg
            # Eğer "6x200 ml" gibi çoklu paketse regex_srv porsiyondur
            if regex_srv > 0:
                serving_quantity = regex_srv
            quantity_source = "regex"
            if regex_unit in ("ml", "l", "lt", "cc"):
                quantity_unit = "ml"

    # quantity_info: UI'ın göstereceği özet (birim doğru gösterilsin)
    def _fmt_qty(qty: float, unit: str) -> str:
        """Miktarı insan-dostu formatla: 330 ml, 1.5 L, 200 g, 1 kg."""
        if unit == "ml":
            if qty >= 1000:
                liters = qty / 1000
                # Tam sayıysa "1 L", değilse "1.5 L"
                return f"{liters:.0f} L" if liters == int(liters) else f"{liters:.1f} L".replace(".", ",")
            # 330.0 → "330 ml" (tam sayı göster)
            return f"{qty:.0f} ml"
        elif unit == "l":
            return f"{qty:.1f} L".replace(".", ",").replace(",0 L", " L")
        else:  # g
            if qty >= 1000:
                kg = qty / 1000
                return f"{kg:.0f} kg" if kg == int(kg) else f"{kg:.1f} kg".replace(".", ",")
            return f"{qty:.0f} g"

    if serving_size_text:
        quantity_info = serving_size_text
    elif serving_quantity > 0:
        quantity_info = _fmt_qty(serving_quantity, quantity_unit) + " porsiyon"
    elif product_quantity > 0:
        quantity_info = _fmt_qty(product_quantity, quantity_unit)
    else:
        quantity_info = ""

    # İçerik listesi
    all_ingredients = ""
    if local_product and local_product.get("ingredients_text"):
        all_ingredients = local_product["ingredients_text"]
    elif ingredients:
        all_ingredients = ingredients
        if off_product and off_product.get("ingredients"):
            all_ingredients = ", ".join([i.get("text", "") for i in off_product["ingredients"] if i.get("text")])

    # İçerik VE besin ikisi birden yoksa erken dönüş.
    # Sadece içindekiler eksik ama besin değeri dolu ürünlerde (OFF'da sık)
    # NS + besin kartı gösterilmeye devam etsin — içerik bölümü app'te gizlenir.
    has_nutrition = energy_kcal > 0 or sugars > 0 or sat_fat > 0 or proteins > 0
    if (not all_ingredients or len(all_ingredients.strip()) < 3) and not has_nutrition:
        return {
            "barcode": code,
            "product_name": name,
            "brand": brand,
            "image_url": image_url,
            "data_warning": True,
            "allergens": detect_allergens(name + " " + ingredients),
            "source": source,
            # Porsiyon bilgisi (içerik olmasa bile)
            "product_quantity": product_quantity,
            "serving_quantity": serving_quantity,
            "serving_size_text": serving_size_text,
            "quantity_info": quantity_info,
            "quantity_source": quantity_source,
            "quantity_unit": quantity_unit,
        }

    # Nutri-Score (resmi algoritma)
    grade, points, breakdown = calculate_nutri_score_2024(
        features,
        fvln_pct=fvln_tahmin(all_ingredients),
        product_name=name,
    )

    # Risk analizi
    risks, max_ewg = analyze_ingredients(all_ingredients, risk_scores)
    allergens = detect_allergens(all_ingredients + " " + name)

    # İçerik listesi parse
    ingredient_list = [i.strip() for i in re.split(r'[,;]', all_ingredients) if i.strip()]

    return {
        "barcode": code,
        "product_name": name,
        "brand": brand,
        "image_url": image_url,
        "nutri_score": {"grade": grade, "points": points, "breakdown": breakdown},
        "found_risks": risks,
        "critical_safety_rule": max_ewg >= 9,
        "allergens": allergens,
        "all_ingredients": ingredient_list,
        "source": source,
        # Porsiyon/paket bilgisi (UI toggle için)
        "product_quantity": product_quantity,
        "serving_quantity": serving_quantity,
        "serving_size_text": serving_size_text,
        "quantity_info": quantity_info,
        "quantity_source": quantity_source,
        "quantity_unit": quantity_unit,
    }


@app.post("/analyze-image")
async def analyze_image(file: UploadFile = File(...), request: Request = None):
    if not PYZBAR_AVAILABLE:
        raise HTTPException(status_code=500, detail="Barkod okuma özelliği kullanılamıyor")

    try:
        # Yükleme kısıtı: içerik tipi + boyut (decompress bomb / abuse koruması)
        ct = (file.content_type or "").lower()
        if ct and not ct.startswith("image/"):
            raise HTTPException(status_code=400, detail="Sadece görsel dosyası yüklenebilir")
        contents = await file.read()
        if len(contents) > 10 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Görsel çok büyük (max 10 MB)")
        image = Image.open(io.BytesIO(contents))

        if image.mode != 'RGB':
            image = image.convert('RGB')

        # Barkod oku - orijinal görüntü
        barcodes = pyzbar_decode(image)

        # Bulunamazsa gri tonlamayı dene
        if not barcodes:
            gray_image = image.convert('L')
            barcodes = pyzbar_decode(gray_image)

        # Hala bulunamazsa 2x büyüt
        if not barcodes:
            width, height = image.size
            scaled_image = image.resize((width * 2, height * 2), Image.LANCZOS)
            barcodes = pyzbar_decode(scaled_image)

        if barcodes:
            barcode = barcodes[0].data.decode("utf-8")
            return await lookup_barcode(barcode, request)
        else:
            raise HTTPException(status_code=400, detail="Barkod bulunamadı")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# GRADIO MOUNT — HF Space Gradio SDK için zorunlu
# FastAPI endpoint'ler (/barcode, /health) aynen çalışır,
# Gradio Blocks sadece "API çalışıyor" sayfası gösterir.
# ============================================================
import gradio as gr

with gr.Blocks(title="İçinde Ne Var API", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🥗 **İçinde Ne Var? API**")
    gr.Markdown("Backend çalışıyor. Mobil uygulamadan kullanılır.")
    gr.Markdown("---")
    gr.Markdown("### Erişilebilir endpoint'ler:")
    gr.Markdown("- `GET /barcode/{code}` — Barkod sorgula")
    gr.Markdown("- `POST /analyze-image` — Görselden barkod oku")
    gr.Markdown("- `GET /health` — Sağlık kontrolü")
    gr.Markdown("- `GET /benchmark` — ML benchmark verileri")
    gr.Markdown(f"- Version: 3.1.0 (Gradio mount)")

# FastAPI app'ine Gradio'yu mount et (root path)
app = gr.mount_gradio_app(app, demo, path="/")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
