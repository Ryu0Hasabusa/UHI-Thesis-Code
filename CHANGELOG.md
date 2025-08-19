## Changelog

### 2025-08-19
Refactor:
- Added `greater_tunis_lcz_repo/scripts/setup.R` for one-time dependency install.
- Added `greater_tunis_lcz_repo/scripts/common.R` (ROI, LCZ map, MODIS, Landsat helpers).
- Simplified run scripts: `run_lcz_only.R`, `run_lcz_modis.R`, `run_lcz_landsat.R`.
- Updated top-level and nested READMEs.
- Removed legacy combined runner and per-dataset helper scripts.
- Added GitHub Actions workflow `lcz.yml` for automated LCZ generation.

### Earlier
Initial repository setup.
