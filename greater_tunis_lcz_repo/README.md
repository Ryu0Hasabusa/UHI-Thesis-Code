# Greater Tunis LCZ Map (Standalone Repo Template)

Self-contained structure to generate the Greater Tunis Local Climate Zone (LCZ) map using the LCZ4r package.

## Contents

- `scripts/setup_and_run.R` : Installs dependencies (prefers local LCZ4r or GitHub) and produces the LCZ map.
- `scripts/roi_config.json` : Optional override configuration (bbox, flags).
- `renv/` infrastructure: (You can initialize to lock package versions.)
- `.github/workflows/build-map.yml` : CI workflow to run the script and upload artifacts.
- `scripts/get_modis_latest.R` : Optional automatic fetch of the latest MOD11A1 LST (Day & Night) tiles.
- `scripts/get_landsat_latest.R` : Optional STAC-based download of a recent low-cloud Landsat C2 L2 scene.

## Quick Start (Local)
```r
source("scripts/setup_and_run.R")
```
Outputs land in `output/`.

## Environment Variables
| Variable | Purpose | Default |
|----------|---------|---------|
| `LCZ4R_LOCAL_PATH` | Local path to LCZ4r source | `../LCZ4r` |
| `LCZ4R_GITHUB_REPO`| GitHub repo for LCZ4r | `ByMaxAnjos/LCZ4r` |
| `LCZ4R_GITHUB_REF` | Git ref (branch/tag/commit) | `main` |
| `LCZ4R_FORCE_REINSTALL` | Force reinstall LCZ4r | `FALSE` |
| `GT_USE_EXACT` | Use exact OSM polygons first | `TRUE` |
| `GT_MANUAL_BBOX` | xmin,xmax,ymin,ymax | (none) |
| `ENABLE_MODIS` | If TRUE, download latest MOD11A1 | `FALSE` |
| `ENABLE_LANDSAT` | If TRUE, fetch latest Landsat scene | `FALSE` |
| `LANDSAT_START` | Landsat search start date | `today-30d` |
| `LANDSAT_END` | Landsat search end date | `today` |
| `LANDSAT_MAX_CLOUD` | Max cloud % filter | `10` |
| `LANDSAT_BANDS` | Comma list bands to download | `SR_B2,..,ST_B10,QA_PIXEL` |
| `EARTHDATA_USER` | NASA Earthdata username (for MODIS) | (none) |
| `EARTHDATA_PASS` | NASA Earthdata password (for MODIS) | (none) |

You can also supply a config JSON (`scripts/roi_config.json`) with keys `manual_bbox` and `use_exact`; env vars override JSON.

## CI
The provided GitHub Actions workflow:
- Sets up R and system deps (sf / terra requirements on Linux).
- Installs LCZ4r and runs the script.
- Uploads resulting TIFF + ROI geopackage as artifacts.
- If `ENABLE_MODIS` and credentials secrets are provided, also downloads latest MOD11A1 and stores under `output/MODIS/MOD11A1`.

To enable: copy this directory as a repo root and push. Optionally enable Actions in repo settings.

## Reproducibility
You can initialize renv:
```r
install.packages("renv")
renv::init()
```
Then re-run the script; a lockfile will capture versions.

## License
MIT for script scaffolding. LCZ4r retains its own license.
