# İçinde Ne Var? — *What's Inside?*

A mobile app that scans a food product's barcode and explains what is really in it:
an official-algorithm **Nutri-Score**, **risky additives** with evidence levels,
**allergen warnings** personalised to the user, and portion-aware nutrition values.
Built for the Turkish market (Turkish / English UI).

## Features

- **Barcode scanning** with the camera or from a gallery photo (on-device, ML Kit via `mobile_scanner`)
- **Search by product name or brand** with Turkish-aware matching (`ı/i`, `ş/s`, `ğ/g` …)
- **Nutri-Score (2023 algorithm)** computed server-side, with a per-nutrient points breakdown
  and beverage/food thresholds
- **Additive risk analysis**: ~190 additives scored with EWG-style 1–10 scores and evidence
  levels (strong / moderate / limited) referencing EFSA, FDA and JECFA assessments
- **Personal allergen profile**: products that contain the user's allergens are flagged
- **Portion toggle**: per 100 g, per serving, per package or a custom amount
- **Compare** two products side by side
- **Favorites, scan history and an offline cache** (SQLite) — previously scanned products
  open without a connection
- Share a product summary

## Architecture

```
┌────────────────────┐   HTTPS / JSON   ┌──────────────────────────────┐
│  Flutter app       │ ───────────────▶ │  FastAPI backend             │
│  (Android)         │                  │  Hugging Face Space          │
│                    │                  │                              │
│  • mobile_scanner  │                  │  • DuckDB over Parquet       │
│  • sqflite cache   │                  │    (~4.5M products)          │
│  • TR / EN UI      │                  │  • Nutri-Score engine        │
└────────────────────┘                  │  • additive & allergen rules │
                                        │  • rate limiting             │
                                        └──────────────┬───────────────┘
                                                       │ fallback
                                                       ▼
                                               Open Food Facts API
```

- **App** (`lib/`): Flutter + Material 3, no state-management framework — screens talk to two
  thin services (`ApiService`, `DatabaseService`).
- **Backend** (`backend/`): a single FastAPI service. Product data lives in a Parquet file that
  DuckDB queries directly (4.7× smaller than the original SQLite database). If a barcode is
  missing locally the backend falls back to the Open Food Facts API.
- **Data pipeline** (not in this repository): offline Python jobs that build, clean and
  refresh the product dataset and publish a new Parquet snapshot.

### About the data

This repository contains **code only**:

- The product dataset lives in a private Hugging Face dataset that the backend downloads at
  start-up using a token stored as a Space secret.
- The curated additive risk database is not included either;
  `backend/risk_scores.sample.json` shows its schema with a few entries.

Part of the product data comes from [Open Food Facts](https://world.openfoodfacts.org/) (ODbL).

## Tech stack

| Layer   | Technologies |
|---------|--------------|
| Mobile  | Flutter, Dart, sqflite, mobile_scanner, image_picker, share_plus |
| Backend | Python, FastAPI, DuckDB, Parquet, httpx, Gradio (Space host) |
| Hosting | Hugging Face Spaces, Hugging Face Datasets |

## Running locally

**App**

```bash
flutter pub get
flutter run
flutter test
```

The app talks to the hosted backend (`lib/services/api_service.dart`).

**Backend**

```bash
cd backend
pip install -r requirements.txt gradio uvicorn
python app.py   # serves on http://localhost:7860
```

Without access to the private dataset the backend still starts; barcode lookups then rely on
the Open Food Facts fallback.

## Project structure

```
lib/
  models/      Product, nutrition breakdown, risk ingredient models
  screens/     home, scanner, product detail, compare, history, favorites, settings
  services/    API client, SQLite storage, compare basket
backend/
  app.py                   API: barcode lookup, search, rate limiting, Open Food Facts fallback
  analysis.py              Nutri-Score, allergen and additive-risk rules (stdlib only)
  risk_scores.sample.json  schema sample of the private additive risk database
  tests/                   unit tests for analysis.py
test/          Flutter unit tests (models, API client, storage, compare)
```
