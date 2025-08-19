# Greater Tunis LCZ Map

Lightweight scripts to generate the Greater Tunis Local Climate Zone (LCZ) map and optionally fetch latest MODIS LST or a recent low‑cloud Landsat scene using the `LCZ4r` package.

## Scripts
| File | Purpose |
|------|---------|
| `scripts/setup.R` | One‑time installation of dependencies + `LCZ4r` (local or GitHub). |
| `scripts/common.R` | Shared functions: ROI build, LCZ map generation, MODIS & Landsat download helpers. |
| `scripts/run_lcz_only.R` | Build ROI and generate LCZ raster + PNG. |
| `scripts/run_lcz_modis.R` | LCZ + latest MODIS MOD11A1 Day/Night LST (needs Earthdata creds). |
| `scripts/run_lcz_landsat.R` | LCZ + latest low‑cloud Landsat C2 L2 surface reflectance + thermal stack. |
| `scripts/roi_config.json` | Optional ROI configuration (exact polygons / manual bbox). |

Deprecated legacy scripts (`setup_and_run.R`, `get_modis_latest.R`, `get_landsat_latest.R`) have been replaced internally—remove them once no external tooling calls them.

## Quick Start
One‑time setup (from repository root):
```r
Rscript greater_tunis_lcz_repo/scripts/setup.R
```

Generate LCZ only:
```r
Rscript greater_tunis_lcz_repo/scripts/run_lcz_only.R
```

LCZ + MODIS (needs credentials):
```powershell
$env:EARTHDATA_USER = "your_username"
$env:EARTHDATA_PASS = "your_password"
Rscript greater_tunis_lcz_repo/scripts/run_lcz_modis.R
```

LCZ + Landsat:
```r
Rscript greater_tunis_lcz_repo/scripts/run_lcz_landsat.R
```

Outputs are written under `greater_tunis_lcz_repo/output/`:
- `lcz_map_greater_tunis.tif`, `lcz_map_greater_tunis.png`, `greater_tunis_roi.gpkg`
- Subfolders: `MODIS/` and `LANDSAT/` when respective downloads occur

## Configuration
Priority: Environment variable > `roi_config.json` > internal defaults.

Key environment variables:
- `LCZ4R_LOCAL_PATH`, `LCZ4R_GITHUB_REPO`, `LCZ4R_GITHUB_REF`, `LCZ4R_FORCE_REINSTALL`
- `GT_USE_EXACT` (TRUE/FALSE), `GT_MANUAL_BBOX` (xmin,xmax,ymin,ymax)
- MODIS: `EARTHDATA_USER`, `EARTHDATA_PASS`
- Landsat: `LANDSAT_START`, `LANDSAT_END`, `LANDSAT_MAX_CLOUD`, `LANDSAT_BANDS`

## Troubleshooting
- Missing packages: re-run `setup.R`.
- MODIS failures: check credentials or wait for data availability (may lag UTC date).
- Landsat no scene: relax `LANDSAT_MAX_CLOUD` or widen date range.
- Manual ROI: set `GT_MANUAL_BBOX` or edit `roi_config.json`.

## License
MIT for these helper scripts. Refer to `LCZ4r` for its own licensing.
