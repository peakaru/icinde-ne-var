---
title: Icinde Ne Var API
emoji: 🥗
colorFrom: green
colorTo: blue
sdk: gradio
sdk_version: "4.44.0"
app_file: app.py
pinned: false
---

# İçinde Ne Var? — Backend API

FastAPI service (mounted in a Gradio app so it can run as a Hugging Face Space).

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/barcode/{code}` | Product lookup: Nutri-Score, additive risks, allergens, portion info |
| GET | `/search?q=...` | Search by product name or brand (Turkish-aware) |
| GET | `/health` | Health check, including which risk database is loaded |
| GET | `/legal` | Privacy policy page |

## Data

- **Products**: a Parquet snapshot queried with DuckDB. It lives in a private Hugging Face
  dataset and is downloaded at start-up with the `HF_TOKEN` Space secret. Missing barcodes
  fall back to the Open Food Facts API.
- **Additive risks**: `risk_scores.json` (190 entries) lives in the same private dataset and
  is downloaded the same way; it is not included in this repository. `risk_scores.sample.json`
  shows the schema with a few entries. Outside a Space the backend falls back to the sample so
  it starts from a clean checkout; on the Space it never does, and `/health` reports which
  one is loaded (`risk_db`: `full`, `sample` or `missing`).

## Tests

```
python -m unittest discover -s backend/tests
```

The analysis rules (Nutri-Score, allergens, additive matching) live in `analysis.py`, which
has no third-party dependencies, so the tests run without installing anything.
