## Changelog

### 2025-08-19
Refactor:
- Added `scripts/setup.R` for one-time dependency install.
- Added `scripts/common.R` (ROI, LCZ map, MODIS, Landsat helpers).
- Simplified run scripts: `run_lcz_only.R`, `run_lcz_modis.R`, `run_lcz_landsat.R`.
- Updated top-level and nested READMEs.
- Removed legacy combined runner and per-dataset helper scripts.
- Added GitHub Actions workflow `lcz.yml` for automated LCZ generation.

Post-refactor adjustments (2025-08-20):
- Removed obsolete `greater_tunis_lcz_repo/` path prefixes in docs & workflow.
- Preparing for repository rename; update badges once rename finalized on GitHub.

### 2025-08-20 (later)
Landsat workflow simplification:
- Removed automated Google Earth Engine Landsat downloader (`scripts/landsatGEE.py`).
- `run_lcz_landsat.R` now expects a user-supplied local multi-band Landsat GeoTIFF (env var `LANDSAT_STACK` or file under `input/LANDSAT/`).
- Output folder renamed from `output/LANDSAT_GEE/` to `output/LANDSAT/`.
- README updated accordingly.

### Earlier
Initial repository setup.
