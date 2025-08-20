# greater_tunis_lcz_repo

<!-- Badge will need repo rename on GitHub; update owner/name below after renaming repository if desired -->
[![LCZ Map Workflow](https://github.com/Ryu0Hasabusa/greater_tunis_lcz_repo/actions/workflows/lcz.yml/badge.svg)](https://github.com/Ryu0Hasabusa/greater_tunis_lcz_repo/actions/workflows/lcz.yml)

Workflow for generating Local Climate Zone (LCZ) map and optional satellite datasets (MODIS LST, Landsat) for Greater Tunis.

## Structure
Key directory: `scripts`

Scripts:
- `setup.R` – one-time install of required R packages and the `LCZ4r` package (local path or GitHub).
- `common.R` – shared helper functions (ROI build, LCZ map generation, MODIS & Landsat download functions).
- `run_lcz_only.R` – build ROI + generate LCZ raster & preview PNG.
- `run_lcz_modis.R` – LCZ + latest available MODIS MOD11A1 (Day/Night LST) within last ~7 days (needs EARTHDATA credentials).
- `run_lcz_landsat.R` – LCZ + processing of a user-provided local Landsat stack (manual; automation removed 2025-08-20).
	Provide a multi-band GeoTIFF via env var `LANDSAT_STACK` or place it under `input/LANDSAT/`.

Config file: `scripts/roi_config.json` (can override ROI behavior). Environment variables override JSON.

Outputs go to `output/`:
- `lcz_map_greater_tunis.tif` – LCZ raster (byte palette)
- `lcz_map_greater_tunis.png` – quicklook PNG
- `greater_tunis_roi.gpkg` – ROI polygon
- `MODIS/` and `LANDSAT/` subfolders when respective runs are used

## One-time setup
From repository root (PowerShell on Windows):

```powershell
Rscript scripts/setup.R
```

Optional environment overrides before running setup:
- `LCZ4R_LOCAL_PATH` (default ../LCZ4r) – install locally if present
- `LCZ4R_GITHUB_REPO` (default ByMaxAnjos/LCZ4r)
- `LCZ4R_GITHUB_REF` (default main)
- `LCZ4R_FORCE_REINSTALL=TRUE` to force reinstall

## Running

### LCZ only
```powershell
Rscript scripts/run_lcz_only.R
```

### LCZ + MODIS LST
Requires NASA Earthdata login:
```powershell
$env:EARTHDATA_USER = "your_username"
$env:EARTHDATA_PASS = "your_password"
Rscript scripts/run_lcz_modis.R
```

### LCZ + Landsat (manual input)
Prepare a multi-band Landsat GeoTIFF (e.g. containing SR_B2..SR_B7 and ST_B10 or precomputed ST_K/ST_C).

Options to point the script at your file:
1. Set an environment variable `LANDSAT_STACK` to the full path.
2. Or place the file somewhere under `input/LANDSAT/` (the newest file or one containing 'landsat' in its name is chosen).

Then run:
```powershell
Rscript scripts/run_lcz_landsat.R
```

Output products go to `output/LANDSAT/`:
- `landsat_LST_C.tif` (normalized Celsius surface temperature)
- `landsat_LST_C.png` (quicklook)

## ROI customization
`scripts/roi_config.json` keys:
- `GT_USE_EXACT` (true/false) – attempt exact OSM polygons before falling back to bbox
- `GT_MANUAL_BBOX` – four comma-separated numbers (xmin,xmax,ymin,ymax) to override automatic polygon building

Environment variables `GT_USE_EXACT` / `GT_MANUAL_BBOX` override JSON values.

## GitHub Actions workflow
The included workflow `/.github/workflows/lcz.yml` runs weekly (cron) and can be triggered manually. It:
1. Sets up R and system libraries (GDAL, PROJ, GEOS, udunits).
2. Runs `setup.R` then `run_lcz_only.R`.
3. If `EARTHDATA_USER` / `EARTHDATA_PASS` secrets are defined, also runs `run_lcz_modis.R`.
4. Uploads the `output/` directory as an artifact named `lcz-output`.

To enable MODIS in CI, add repository secrets:
- `EARTHDATA_USER`
- `EARTHDATA_PASS`

To add Landsat in CI you would first need to stage a stack file in the workflow (e.g. via artifact/download); the previous automated GEE retrieval was removed.

## Troubleshooting
- Missing packages: rerun `setup.R`.
- MODIS download fails: verify EARTHDATA credentials and wait a day if data not yet published.
- Landsat processing: ensure your supplied stack includes either ST_C, ST_K, or raw ST_B10; script auto-detects and scales to Celsius.

## License
See individual component licenses; LCZ4r license in its own directory.
