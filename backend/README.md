---
title: Peakaru Backend V2
emoji: 🥗
colorFrom: green
colorTo: blue
sdk: gradio
sdk_version: "4.44.0"
app_file: app.py
pinned: false
hardware: cpu-basic
---

# İçinde Ne Var? — Backend API

FastAPI service (mounted in a Gradio app so it can run as a Hugging Face Space).

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/barcode/{code}` | Product lookup: Nutri-Score, additive risks, allergens, portion info |
| GET | `/search?q=...` | Search by product name or brand (Turkish-aware) |
| GET | `/health` | Health check |
| GET | `/legal` | Privacy policy page |

## Data

- **Products**: a Parquet snapshot queried with DuckDB. It lives in a private Hugging Face
  dataset and is downloaded at start-up with the `HF_TOKEN` Space secret. Missing barcodes
  fall back to the Open Food Facts API.
- **Additive risks**: `risk_scores.json` (190 entries, not included in this repository).
  `risk_scores.sample.json` shows the schema with a few entries; the backend falls back to
  it when the full file is missing, so it still starts locally.

## Tests

```
python -m unittest discover -s backend/tests
```

The analysis rules (Nutri-Score, allergens, additive matching) live in `analysis.py`, which
has no third-party dependencies, so the tests run without installing anything.
