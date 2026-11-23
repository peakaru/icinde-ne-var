"""Unit tests for backend/analysis.py (stdlib only: python -m unittest discover backend/tests)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from analysis import (  # noqa: E402
    ProductFeatures,
    _tr_norm,
    analyze_ingredients,
    calculate_nutri_score_2024,
    detect_allergens,
    fold_i,
    fvln_tahmin,
    is_beverage,
    normalize_sodium_mg,
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


class BeverageTest(unittest.TestCase):
    def test_detection(self):
        self.assertTrue(is_beverage("Şeftalili Buzlu Çay"))
        self.assertTrue(is_beverage("ENERJİ İÇECEĞİ"))
        self.assertTrue(is_beverage("Coca-Cola Zero"))
        self.assertFalse(is_beverage("ChocoLait"))
        self.assertFalse(is_beverage("Fındıklı Gofret"))


class NutriScoreTest(unittest.TestCase):
    def test_hazelnut_spread_is_e(self):
        f = ProductFeatures(energy_100g=539, sugars_100g=56.3, saturated_fat_100g=10.6,
                            sodium_100g=41, proteins_100g=6.3, fiber_100g=0)
        grade, points, breakdown = calculate_nutri_score_2024(f, fvln_pct=0, product_name="Nutella")
        self.assertEqual(grade, "E")
        self.assertEqual(points, 26)
        self.assertEqual(breakdown["sugars"]["points"], 10)

    def test_plain_pasta_is_a(self):
        f = ProductFeatures(energy_100g=375, sugars_100g=0, saturated_fat_100g=0,
                            sodium_100g=0, proteins_100g=13, fiber_100g=3)
        grade, _, _ = calculate_nutri_score_2024(f, product_name="Spaghetti")
        self.assertEqual(grade, "A")

    def test_water_is_beverage_a(self):
        grade, _, _ = calculate_nutri_score_2024(ProductFeatures(), product_name="Maden Suyu")
        self.assertEqual(grade, "A")

    def test_fvln_lowers_score(self):
        f = ProductFeatures(energy_100g=250, sugars_100g=20, saturated_fat_100g=0,
                            sodium_100g=0, proteins_100g=1, fiber_100g=2)
        _, without, _ = calculate_nutri_score_2024(f, fvln_pct=0, product_name="Reçel")
        _, with_fruit, _ = calculate_nutri_score_2024(f, fvln_pct=85, product_name="Reçel")
        self.assertLess(with_fruit, without)


class HelperTest(unittest.TestCase):
    def test_sodium_units(self):
        self.assertAlmostEqual(normalize_sodium_mg(0.4), 400)
        self.assertEqual(normalize_sodium_mg(492), 492)
        self.assertEqual(normalize_sodium_mg(None), 0)

    def test_fvln_estimate(self):
        self.assertEqual(fvln_tahmin("Elma %35, Armut %20, şeker"), 55)
        self.assertEqual(fvln_tahmin(""), 0)


if __name__ == "__main__":
    unittest.main()
