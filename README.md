# UHI-Thesis-Code

Workflow for generating Local Climate Zone (LCZ) map and optional satellite datasets (MODIS LST, Landsat) for Greater Tunis.

## Structure
Key directory: `greater_tunis_lcz_repo/scripts`

Scripts:
- `setup.R` – one-time install of required R packages and the `LCZ4r` package (local path or GitHub).
- `common.R` – shared helper functions (ROI build, LCZ map generation, MODIS & Landsat download functions).
- `run_lcz_only.R` – build ROI + generate LCZ raster & preview PNG.
- `run_lcz_modis.R` – LCZ + latest available MODIS MOD11A1 (Day/Night LST) within last ~7 days (needs EARTHDATA credentials).
- `run_lcz_landsat.R` – LCZ + latest low-cloud Landsat Collection 2 Level-2 surface reflectance + thermal stack.
- Deprecated stubs kept temporarily: `setup_and_run.R`, `get_modis_latest.R`, `get_landsat_latest.R` (each immediately stops with a message). These can be deleted once no external references remain.

Config file: `scripts/roi_config.json` (can override ROI behavior). Environment variables override JSON.

Outputs go to `greater_tunis_lcz_repo/output/`:
- `lcz_map_greater_tunis.tif` – LCZ raster (byte palette)
- `lcz_map_greater_tunis.png` – quicklook PNG
- `greater_tunis_roi.gpkg` – ROI polygon
- `MODIS/` and `LANDSAT/` subfolders when respective runs are used

## One-time setup
From repository root (PowerShell on Windows):

```powershell
Rscript greater_tunis_lcz_repo/scripts/setup.R
```

Optional environment overrides before running setup:
- `LCZ4R_LOCAL_PATH` (default ../LCZ4r) – install locally if present
- `LCZ4R_GITHUB_REPO` (default ByMaxAnjos/LCZ4r)
- `LCZ4R_GITHUB_REF` (default main)
- `LCZ4R_FORCE_REINSTALL=TRUE` to force reinstall

## Running

### LCZ only
```powershell
Rscript greater_tunis_lcz_repo/scripts/run_lcz_only.R
```

### LCZ + MODIS LST
Requires NASA Earthdata login:
```powershell
$env:EARTHDATA_USER = "your_username"
$env:EARTHDATA_PASS = "your_password"
Rscript greater_tunis_lcz_repo/scripts/run_lcz_modis.R
```

### LCZ + Landsat
```powershell
Rscript greater_tunis_lcz_repo/scripts/run_lcz_landsat.R
```
Optional env vars:
- `LANDSAT_START` (default 30 days ago)
- `LANDSAT_END` (default today)
- `LANDSAT_MAX_CLOUD` (default 10)
- `LANDSAT_BANDS` (default SR_B2,SR_B3,SR_B4,SR_B5,SR_B6,SR_B7,ST_B10,QA_PIXEL)

## ROI customization
`scripts/roi_config.json` keys:
- `GT_USE_EXACT` (true/false) – attempt exact OSM polygons before falling back to bbox
- `GT_MANUAL_BBOX` – four comma-separated numbers (xmin,xmax,ymin,ymax) to override automatic polygon building

Environment variables `GT_USE_EXACT` / `GT_MANUAL_BBOX` override JSON values.

## Housekeeping
Remove deprecated stub scripts once no external automation references them.

## Troubleshooting
- Missing packages: rerun `setup.R`.
- MODIS download fails: verify EARTHDATA credentials and wait a day if data not yet published.
- Landsat no scenes: increase date range or cloud threshold (`LANDSAT_MAX_CLOUD`).

## License
See individual component licenses; LCZ4r license in its own directory.
