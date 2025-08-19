# Greater Tunis LCZ Map (Standalone Repo Template)

Self-contained structure to generate the Greater Tunis Local Climate Zone (LCZ) map using the LCZ4r package.

## Contents

- `scripts/setup_and_run.R` : Installs dependencies (prefers local LCZ4r or GitHub) and produces the LCZ map.
- `scripts/roi_config.json` : Optional override configuration (bbox, flags).
- `renv/` infrastructure: (You can initialize to lock package versions.)
- `.github/workflows/build-map.yml` : CI workflow to run the script and upload artifacts.

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

You can also supply a config JSON (`scripts/roi_config.json`) with keys `manual_bbox` and `use_exact`; env vars override JSON.

## CI
The provided GitHub Actions workflow:
- Sets up R and system deps (sf / terra requirements on Linux).
- Installs LCZ4r and runs the script.
- Uploads resulting TIFF + ROI geopackage as artifacts.

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
