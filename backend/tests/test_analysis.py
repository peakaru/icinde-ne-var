"""Unit tests for backend/analysis.py (stdlib only: python -m unittest discover backend/tests)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from analysis import (  # noqa: E402
    NutriCategory,
    Nutrients,
    _tr_norm,
    allergen_info,
    allergens_from_off_tags,
    analyze_ingredients,
    compute_nutri_score,
    detect_allergens,
    detect_allergens_detailed,
    evaluate_nutri_score,
    fold_i,
    fvln_tahmin,
    has_non_nutritive_sweeteners,
    is_beverage,
    normalize_sodium_mg,
    nutri_category,
    nutri_score_from_off,
)


class FoldTest(unittest.TestCase):
    def test_turkish_and_english_uppercase(self):
        self.assertEqual(fold_i("FINDIK"), fold_i("fındık"))
        self.assertEqual(fold_i("PEYNİR"), "peynir")
        self.assertEqual(fold_i("MILK"), "milk")

    def test_search_normaliser_handles_dotted_capital_i(self):
        self.assertEqual(_tr_norm("İçim"), "icim")
        self.assertEqual(_tr_norm("IŞIK"), "isik")
        self.assertEqual(_tr_norm("Ülker Çikolata"), "ulker cikolata")


class AllergenTest(unittest.TestCase):
    def assertAllergens(self, text, expected):
        self.assertEqual(sorted(detect_allergens(text)), sorted(expected), text)

    def test_uppercase_turkish_labels(self):
        self.assertAllergens("BUĞDAY UNU, ŞEKER, FINDIK (%13)", ["gluten", "kuruyemiş"])
        self.assertAllergens("TON BALIĞI, AYÇİÇEK YAĞI", ["balık"])
        self.assertAllergens("KEREVİZ, SÜLFİT", ["kereviz", "sülfit"])
        self.assertAllergens("PEYNİR, CEVİZ", ["süt", "kuruyemiş"])

    def test_turkish_suffixes(self):
        self.assertAllergens("pastörize inek sütü", ["süt"])
        self.assertAllergens("İNEK SÜTÜ", ["süt"])
        self.assertAllergens("sütlü çikolata", ["süt"])
        self.assertAllergens("whole eggs", ["yumurta"])

    def test_negations_and_lookalikes_are_not_allergens(self):
        self.assertAllergens("Pirinç unu, şeker. Glutensizdir.", [])
        self.assertAllergens("gluten içermez", [])
        self.assertAllergens("gluten-free oats", [])
        self.assertAllergens("sütsüz", [])
        self.assertAllergens("Şeker, kakao yağı (cocoa butter)", [])
        self.assertAllergens("eggplant, tomato", [])
        self.assertAllergens("BALIK KRAKER", [])

    def test_plain_lowercase_still_works(self):
        self.assertAllergens("şeker, fındık, süt tozu", ["süt", "kuruyemiş"])
        self.assertAllergens("may contain traces of peanut", ["kuruyemiş"])

    def test_european_labels(self):
        # Gerçek Nutella etiketi (Fransızca): fındık ve soya bulunmalı,
        # "Sans gluten" gluten sayılmamalı
        self.assertAllergens(
            "Sucre, huile de palme, NOISETTES 13%, cacao maigre 7,4%, LAIT écrémé "
            "en poudre 6,6%, LACTOSERUM en poudre, émulsifiants: lécithines [SOJA), "
            "vanilline. Sans gluten.",
            ["süt", "kuruyemiş", "soya"])
        self.assertAllergens("Weizenmehl, Vollmilchpulver, Haselnüsse, Eier",
                             ["gluten", "süt", "kuruyemiş", "yumurta"])
        self.assertAllergens("farina di frumento, uova, senape", ["gluten", "yumurta", "hardal"])
        self.assertAllergens("Sodium Metabisulphite, conservateur (E223)", ["sülfit"])

    def test_european_negations_and_lookalikes(self):
        self.assertAllergens("Harina de maíz, sal. Sin gluten.", [])
        self.assertAllergens("Zucker, Kakaobutter, Kakaomasse", [])
        self.assertAllergens("sucre, beurre de cacao", [])
        self.assertAllergens("lait de coco, sucre", [])
        self.assertAllergens("Buchweizenmehl, Salz", [])
        self.assertAllergens("Zartbitterschokolade geraspelt", [])
        self.assertAllergens("sel, poivre, noix de muscade", [])
        self.assertAllergens("Mandelmilch (Wasser, Mandeln 7%)", ["kuruyemiş"])
        self.assertAllergens("Sedano Rigati makarna, durum buğdayı irmiği", ["gluten"])

    def test_off_markup_accents_and_compounds(self):
        # OFF alerjenleri _alt çizgi_ ile vurgular; aksansız ve bileşik yazımlar
        self.assertAllergens("farine de _blé_, _œufs_, lécithines (_soja_)",
                             ["gluten", "yumurta", "soya"])
        self.assertAllergens("farine de BLE, sucre", ["gluten"])
        self.assertAllergens("yogurt, sut tozu, bugday unu", ["süt", "gluten"])
        self.assertAllergens("soybeans, sojalecithin", ["soya"])
        self.assertAllergens("magere melkpoeder, tarwebloem", ["süt", "gluten"])
        self.assertAllergens("sodium caseinate, milkfat", ["süt"])
        self.assertAllergens("Antep fıstığı, yerfıstığı", ["kuruyemiş"])

    def test_non_gluten_flours_coconut_and_caramel(self):
        self.assertAllergens("brown rice flour, corn flour, chickpea flour", [])
        self.assertAllergens("enriched flour (niacin, iron)", ["gluten"])
        self.assertAllergens("mısır irmiği, tuz", [])
        self.assertAllergens("karabuğday unu, tuz", [])
        # Hindistan cevizi AB/TGK listesinde kuruyemiş değil
        self.assertAllergens("hindistan cevizi rendesi, şeker", [])
        self.assertAllergens("lait de coco (extrait de noix de coco)", [])
        # Sülfitli amonyak karamel (E150d) sülfit alerjeni değil
        self.assertAllergens("renklendirici (amonyak sülfit karamel)", [])
        self.assertAllergens("sodyum metabisülfit", ["sülfit"])
        self.assertAllergens("yulaf ezmesi", ["gluten"])
        self.assertAllergens("cream soda flavour, sugar", [])
        self.assertAllergens("product code 123, sugar", [])

    def test_seafood_and_lupin(self):
        self.assertAllergens("midye, pirinç, soğan", ["yumuşakça"])
        self.assertAllergens("karides, kalamar", ["kabuklu", "yumuşakça"])
        self.assertAllergens("acı bakla unu", ["lupin"])
        # "sert kabuklu meyveler" kuruyemiştir, kabuklu deniz ürünü değil
        self.assertAllergens("Sert kabuklu meyveler içerebilir", ["kuruyemiş"])
        self.assertAllergens("istiridye mantarı, tuz", [])


class AllergenTraceTest(unittest.TestCase):
    def test_turkish_trace_clause(self):
        c, t = detect_allergens_detailed(
            "Buğday unu, şeker, süt tozu. Eser miktarda fındık, soya ve susam içerebilir.")
        self.assertEqual(c, ["süt", "gluten"])
        self.assertEqual(t, ["soya", "kuruyemiş", "susam"])

    def test_trace_clause_after_ingredients_without_period(self):
        c, t = detect_allergens_detailed("Yoğurt, buğday unu, yumurta, tuz, iz miktarda kereviz içerebilir")
        self.assertEqual(c, ["süt", "gluten", "yumurta"])
        self.assertEqual(t, ["kereviz"])

    def test_other_languages(self):
        self.assertEqual(detect_allergens_detailed(
            "sugar, milk powder. May contain traces of nuts and wheat."),
            (["süt"], ["gluten", "kuruyemiş"]))
        self.assertEqual(detect_allergens_detailed("sucre, farine de blé. Peut contenir : Soja."),
                         (["gluten"], ["soya"]))
        self.assertEqual(detect_allergens_detailed(
            "Zucker, Weizenmehl. Kann Spuren von Haselnüssen enthalten."),
            (["gluten"], ["kuruyemiş"]))

    def test_ingredient_also_in_trace_clause_stays_contained(self):
        c, t = detect_allergens_detailed("Fındık (%40), şeker. Eser miktarda fındık ve süt içerebilir.")
        self.assertEqual((c, t), (["kuruyemiş"], ["süt"]))

    def test_long_unmarked_list_is_not_downgraded(self):
        text = ("Mısır unu, tuz, şeker, peynir tozu, süt tozu, buğday nişastası, soya lesitini, "
                "fındık parçaları, aroma verici, renklendirici, tuz, şeker, fındık içerebilir")
        self.assertEqual(detect_allergens_detailed(text)[1], [])

    def test_off_tags_merge(self):
        allergens, traces = allergen_info(
            "şeker, kakao. Eser miktarda süt içerebilir.",
            {"allergens_tags": ["en:milk"], "traces_tags": ["en:nuts"]})
        self.assertEqual(allergens, ["süt", "kuruyemiş"])
        self.assertEqual(traces, ["kuruyemiş"])   # OFF "içerir" diyorsa süt eser değil
        self.assertEqual(allergens_from_off_tags("en:milk,en:apple"), ["süt"])


class IngredientRiskTest(unittest.TestCase):
    RISKS = {
        "E250": {"name": "Sodyum nitrit", "keywords": ["sodyum nitrit", "nitrit"],
                 "ewg_score": 9, "evidence": "strong"},
        "E330": {"name": "Sitrik asit", "keywords": ["sitrik asit", "citric acid"],
                 "ewg_score": 1},
    }

    def test_uppercase_turkish_ingredients_match(self):
        risks, max_ewg = analyze_ingredients("DANA ETİ, TUZ, SODYUM NİTRİT, SİTRİK ASİT", self.RISKS)
        self.assertEqual({r["name"] for r in risks}, {"Sodyum nitrit", "Sitrik asit"})
        self.assertEqual(max_ewg, 9)

    def test_code_key_matches(self):
        risks, _ = analyze_ingredients("şeker, e250", self.RISKS)
        self.assertEqual([r["name"] for r in risks], ["Sodyum nitrit"])

    MORE = {
        "E220": {"name": "Kükürt dioksit", "keywords": ["kükürt dioksit", "sülfit"]},
        "E223": {"name": "Sodyum metabisülfit", "keywords": ["sodyum metabisülfit"]},
        "E471": {"name": "Mono- ve digliseritler", "keywords": ["mono ve digliseritler",
                                                                "emülgatör"]},
        "E472e": {"name": "DATEM", "keywords": ["e472e"]},
        "E322": {"name": "Lesitin", "keywords": ["lesitin", "lecithin"]},
        "E202": {"name": "Potasyum sorbat", "keywords": ["potasyum sorbat"]},
        "E211": {"name": "Sodyum benzoat", "keywords": ["sodyum benzoat"]},
        "E1400": {"name": "Dekstrin", "keywords": ["dekstrin", "dextrin"]},
        "E251": {"name": "Sodyum nitrat", "keywords": ["sodyum nitrat", "nitrat"]},
        "E150": {"name": "Karamel", "keywords": ["karamel", "e150", "e150d"]},
        "E150d": {"name": "Sülfitli amonyak karamel", "keywords": ["e150d"]},
        "E951": {"name": "Aspartam", "keywords": ["aspartam", "tatlandırıcı"]},
    }

    def names(self, text, tags=None):
        return [r["name"] for r in analyze_ingredients(text, self.MORE, tags)[0]]

    def test_every_additive_in_a_group_is_found(self):
        # Eskiden her virgül parçasında yalnızca ilk madde bulunuyordu
        self.assertEqual(self.names("koruyucular (potasyum sorbat ve sodyum benzoat)"),
                         ["Potasyum sorbat", "Sodyum benzoat"])

    def test_longest_name_wins(self):
        self.assertEqual(self.names("koruyucu (sodyum metabisülfit)"), ["Sodyum metabisülfit"])
        self.assertEqual(self.names("renklendirici (E150d)"), ["Sülfitli amonyak karamel"])

    def test_class_words_and_lookalikes_are_not_additives(self):
        self.assertEqual(self.names("emülgatör (ayçiçek lesitini)"), ["Lesitin"])
        self.assertEqual(self.names("tatlandırıcı (sukraloz), karamel parçacıkları"), [])
        self.assertEqual(self.names("maltodekstrin, şeker"), [])
        self.assertEqual(self.names("enriched flour (thiamine mononitrate)"), [])

    def test_e471_vs_e472e(self):
        self.assertEqual(self.names("emülgatör (yağ asitlerinin mono ve digliseridleri)"),
                         ["Mono- ve digliseritler"])
        self.assertEqual(self.names("yağ asitlerinin mono ve digliseridlerinin mono ve "
                                    "diasetil tartarik asit esterleri"), ["DATEM"])

    def test_spelling_variants_and_traces(self):
        self.assertEqual(self.names("E 322, E-202"), ["Lesitin", "Potasyum sorbat"])
        self.assertEqual(self.names("lecithin E322i"), ["Lesitin"])
        self.assertEqual(self.names("şeker. Eser miktarda kükürt dioksit içerebilir."), [])

    def test_off_tags_are_added(self):
        self.assertEqual(self.names("su, şeker", ["en:e202", "en:e322i", "en:e999"]),
                         ["Potasyum sorbat", "Lesitin"])


class BeverageTest(unittest.TestCase):
    def test_detection(self):
        self.assertTrue(is_beverage("Şeftalili Buzlu Çay"))
        self.assertTrue(is_beverage("ENERJİ İÇECEĞİ"))
        self.assertTrue(is_beverage("Coca-Cola Zero"))
        self.assertTrue(is_beverage("Ayran"))
        self.assertTrue(is_beverage("Çikolatalı Süt", 70))
        self.assertTrue(is_beverage("Alkolsüz Bira"))
        self.assertFalse(is_beverage("ChocoLait"))
        self.assertFalse(is_beverage("Fındıklı Gofret"))
        self.assertFalse(is_beverage("Sütlü Çikolata", 540))
        self.assertFalse(is_beverage("Milk Chocolate"))
        self.assertFalse(is_beverage("Pineapple Slices In Pineapple Juice"))
        self.assertFalse(is_beverage("Domates Çorbası"))


class CategoryTest(unittest.TestCase):
    def cat(self, name, **kw):
        return nutri_category(name, Nutrients(**kw) if kw else None)

    def test_cheese(self):
        self.assertTrue(self.cat("Tam Yağlı Beyaz Peynir").cheese)
        self.assertTrue(self.cat("Ziegen-Frischkäse").cheese)
        self.assertFalse(self.cat("Peynirli Kraker").cheese)
        self.assertFalse(self.cat("Fromage blanc 0%").cheese)
        self.assertFalse(self.cat("Cheese flavour crisps").cheese)

    def test_fats_oils_nuts_seeds(self):
        self.assertTrue(self.cat("Natürel Sızma Zeytinyağı").fat_oil_nuts_seeds)
        self.assertTrue(self.cat("Çiğ Fındık").fat_oil_nuts_seeds)
        self.assertTrue(self.cat("Pişirme Kreması").fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Fındıklı Çikolata").fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Kestane").fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Ton Balığı Zeytinyağlı").fat_oil_nuts_seeds)

    def test_nut_word_without_fat_dominance(self):
        # Adında fındık/ceviz geçse de enerjisi şekerden/nişastadan gelen ürün genel grupta
        self.assertFalse(self.cat("Probiyotik Bowl Ahududu Yulaf Ceviz", energy_kcal=79,
                                  sugars=9.7, fat=1.2).fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Magnum Crack Badem", energy_kcal=352, sugars=30,
                                  fat=22).fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Ceviz Reçeli", energy_kcal=299, sugars=55).fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Sürülebilir Fındık Ezmesi", energy_kcal=555, sugars=57,
                                  fat=34).fat_oil_nuts_seeds)
        self.assertFalse(self.cat("Antep Fıstığı Aromalı Mısır Çerez").fat_oil_nuts_seeds)
        # Gerçek yağ/kuruyemiş ürünleri grupta kalır
        self.assertTrue(self.cat("Sade Fıstık Ezmesi", energy_kcal=554, sugars=4.5,
                                 fat=34.3).fat_oil_nuts_seeds)
        self.assertTrue(self.cat("Pişirme Kreması", energy_kcal=190, sugars=3,
                                 fat=18).fat_oil_nuts_seeds)
        self.assertTrue(self.cat("Tütsü Aromalı Karışık Kuruyemiş", energy_kcal=550, sugars=8.8,
                                 fat=26.1).fat_oil_nuts_seeds)

    def test_gazoz_is_beverage(self):
        self.assertTrue(self.cat("Limon Aromalı Datça Gazozu 200 Ml", energy_kcal=38).beverage)

    def test_not_applicable(self):
        for name in ("Efes Pilsen Bira", "Sofra Tuzu", "Karabiber", "Elma Sirkesi",
                     "Multivitamin Efervesan Tablet", "Bebek Maması"):
            self.assertTrue(self.cat(name).not_applicable, name)
        for name in ("Kekikli Zeytin", "Cheese And Herbs", "Salt & Vinegar Chips",
                     "Alkolsüz Bira"):
            self.assertFalse(self.cat(name).not_applicable, name)
        # Kuru kahve/çay değerleri (yüksek enerji): içecek notu anlamsız
        self.assertTrue(self.cat("Granül Kahve", energy_kcal=350).not_applicable)
        self.assertTrue(self.cat("Granül Kahve", energy_kcal=2).beverage)

    def test_water(self):
        n = dict(energy_kcal=0, sugars=0, saturated_fat=0, sodium_mg=10, proteins=0)
        self.assertTrue(self.cat("Doğal Maden Suyu", **n).water)
        self.assertFalse(self.cat("Limonlu Maden Suyu", **n).water)
        self.assertFalse(self.cat("Cherry Sparkling Water", **n).water)

    def test_red_meat(self):
        self.assertTrue(self.cat("Dana Sucuk").red_meat)
        self.assertFalse(self.cat("Hindi Sucuk").red_meat)
        self.assertFalse(self.cat("Beef & Cheese Ravioli").red_meat)


class NutriScoreTest(unittest.TestCase):
    """Beklenen değerler Open Food Facts'in 2023 hesabıyla karşılaştırıldı."""

    def test_hazelnut_spread_is_e(self):
        n = Nutrients(energy_kcal=539, sugars=56.3, saturated_fat=10.6, sodium_mg=42.8,
                      proteins=6.3, fiber=0)
        r = evaluate_nutri_score("Nutella", n)
        self.assertEqual((r.grade, r.score), ("E", 31))     # OFF: e, 31
        self.assertEqual(r.breakdown["sugars"]["points"], 15)
        self.assertEqual(r.breakdown["proteins"]["points"], 0)  # negatif ≥ 11

    def test_plain_pasta_is_a(self):
        n = Nutrients(energy_kcal=359, sugars=3.5, saturated_fat=0.5, sodium_mg=4,
                      proteins=12.5, fiber=3)
        self.assertEqual(evaluate_nutri_score("Spaghetti", n).grade, "A")

    def test_water_is_a(self):
        n = Nutrients(energy_kcal=0, sugars=0, saturated_fat=0, sodium_mg=12, proteins=0)
        self.assertEqual(evaluate_nutri_score("Maden Suyu", n).grade, "A")

    def test_orange_juice_counts_fruit(self):
        # 100% portakal suyu: OFF c (5). Meyve sayılmasa E (11) çıkardı.
        n = Nutrients(energy_kcal=45, sugars=8.9, saturated_fat=0, sodium_mg=0,
                      proteins=0.7, fiber=0.2)
        r = evaluate_nutri_score("Portakal Suyu", n, "Portakal suyu")
        self.assertEqual(r.breakdown["fruits_vegetables_legumes"]["points"], -6)
        self.assertEqual(r.grade, "C")

    def test_sweetened_soft_drink(self):
        n = Nutrients(energy_kcal=0.3, sugars=0, saturated_fat=0, sodium_mg=10, proteins=0)
        r = evaluate_nutri_score("Cola Zero", n, "Su, karbondioksit, tatlandırıcı (aspartam)")
        self.assertEqual(r.breakdown["sweeteners"]["points"], 4)
        self.assertEqual(r.grade, "C")

    def test_breakdown_adds_up(self):
        n = Nutrients(energy_kcal=250, sugars=20, saturated_fat=1.5, sodium_mg=200,
                      proteins=3, fiber=4)
        r = compute_nutri_score(n, NutriCategory(), fvl_pct=50)
        self.assertEqual(sum(v["points"] for v in r.breakdown.values()), r.score)

    def test_fruit_lowers_score(self):
        n = Nutrients(energy_kcal=250, sugars=20, saturated_fat=0, sodium_mg=0,
                      proteins=1, fiber=2)
        without = compute_nutri_score(n, NutriCategory(), fvl_pct=0).score
        with_fruit = compute_nutri_score(n, NutriCategory(), fvl_pct=85).score
        self.assertLess(with_fruit, without)

    def test_missing_nutrient_gives_no_grade(self):
        n = Nutrients(energy_kcal=480, sugars=30, saturated_fat=None, sodium_mg=100, proteins=6)
        r = evaluate_nutri_score("Bisküvi", n)
        self.assertIsNone(r.grade)
        self.assertEqual(r.unavailable_reason, "missing")

    def test_impossible_values_give_no_grade(self):
        n = Nutrients(energy_kcal=0, sugars=50, saturated_fat=0, sodium_mg=0, proteins=0)
        self.assertEqual(evaluate_nutri_score("Lokum", n).unavailable_reason, "implausible")
        # 25 g porsiyon değeri 100 g diye girilmiş çikolata
        n = Nutrients(energy_kcal=141, sugars=12, saturated_fat=4.5, sodium_mg=5, proteins=2.2)
        r = evaluate_nutri_score("Antep Fıstıklı Çikolata", n, data_source="getir")
        self.assertEqual(r.unavailable_reason, "implausible")
        # Aynı ad, gerçek düşük enerjili ürün (dondurma) ya da OFF verisi: dokunulmaz
        self.assertIsNotNone(evaluate_nutri_score("Magnum Mini Badem", n, data_source="getir").grade)
        self.assertIsNotNone(evaluate_nutri_score("Lait au Chocolat", n, data_source="legacy").grade)
        # Aroma adı yoğunluk anlatmaz, ama ürünün kendisi çikolataysa kontrol sürer
        self.assertIsNotNone(evaluate_nutri_score("Fındık Aromalı Kahve", n, data_source="getir").grade)
        self.assertIsNone(evaluate_nutri_score("Portakal Aromalı Çikolata", n, data_source="getir").grade)
        # Fındık ezmesi 116 kcal: porsiyon başı (gerçek ~630)
        self.assertIsNone(evaluate_nutri_score("Fiskobirlik Fındık Ezmesi", n, data_source="getir").grade)
        # Migros da porsiyon değerini 100 g diye yazabiliyor (Nestle 1927 Gofret 28 G: 138 kcal)
        self.assertIsNone(evaluate_nutri_score("Nestle 1927 Sütlü Çikolatalı Gofret", n,
                                               data_source="migros").grade)

    def test_not_applicable(self):
        n = Nutrients(energy_kcal=43, sugars=0, saturated_fat=0, sodium_mg=4, proteins=0.5)
        r = evaluate_nutri_score("Efes Pilsen Bira", n)
        self.assertIsNone(r.grade)
        self.assertEqual(r.unavailable_reason, "not_applicable")

    def test_official_grade_from_off(self):
        off = {"nutriscore": {"2023": {
            "nutriscore_computed": 1, "grade": "b", "score": -1,
            "data": {"is_beverage": 1, "components": {
                "negative": [{"id": "energy", "points": 3}, {"id": "sugars", "points": 3},
                             {"id": "saturated_fat", "points": 0}, {"id": "salt", "points": 0},
                             {"id": "non_nutritive_sweeteners", "points": 0, "value": 0}],
                "positive": [{"id": "proteins", "points": 7}, {"id": "fiber", "points": 0},
                             {"id": "fruits_vegetables_legumes", "points": 0, "value": 0}]}}}}}
        r = nutri_score_from_off(off, Nutrients(energy_kcal=42.5, sugars=3.8))
        self.assertEqual((r.grade, r.score, r.source), ("B", -1, "official"))
        self.assertEqual(r.breakdown["proteins"]["points"], -7)
        self.assertIsNone(nutri_score_from_off({"nutriscore": {"2023": {"grade": "unknown"}}},
                                               Nutrients()))


class HelperTest(unittest.TestCase):
    def test_sodium_units(self):
        self.assertAlmostEqual(normalize_sodium_mg(0.4), 400)
        self.assertEqual(normalize_sodium_mg(492), 492)
        self.assertIsNone(normalize_sodium_mg(None))

    def test_fvln_estimate(self):
        self.assertEqual(fvln_tahmin("Elma %35, Armut %20, şeker"), 55)
        self.assertEqual(fvln_tahmin("Pineapple (69%), Pineapple juice"), 100)
        self.assertEqual(fvln_tahmin("Orange juice"), 100)
        self.assertEqual(fvln_tahmin("", "Jus d'orange"), 100)
        self.assertEqual(fvln_tahmin("", "Portakal Nektarı"), 0)
        self.assertEqual(fvln_tahmin("", "Limonlu Maden Suyu"), 0)
        self.assertEqual(fvln_tahmin("peanuts 13%, sugar"), 0)
        self.assertEqual(fvln_tahmin(""), 0)

    def test_sweeteners(self):
        self.assertTrue(has_non_nutritive_sweeteners("su, aspartam"))
        self.assertTrue(has_non_nutritive_sweeteners("", "en:e330,en:e951"))
        self.assertFalse(has_non_nutritive_sweeteners("şeker, su", "en:e330"))


if __name__ == "__main__":
    unittest.main()
