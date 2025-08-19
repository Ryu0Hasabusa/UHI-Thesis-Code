# Greater Tunis LCZ one-shot script

This repo provides a single R script that:

1. Ensures the LCZ4r package is installed (from local path or remote GitHub `ByMaxAnjos/LCZ4r`).
2. Runs the Greater Tunis LCZ map generation and writes outputs to `LCZ4r_output/`.

## Usage

Clone or download this repo, then in R (>=4.2):

```r
source("setup_and_run.R")
```

That will:
- Install needed CRAN deps.
- Install LCZ4r (prefers a sibling `LCZ4r/` folder if present; otherwise remote GitHub).
- Run the script producing `LCZ4r_output/lcz_map_greater_tunis.tif`.

## Configuration

Environment variables you can set before sourcing:

- `LCZ4R_LOCAL_PATH` : path to a local LCZ4r source (default tries `../LCZ4r`).
- `LCZ4R_GITHUB_REF` : Git ref (branch/tag/commit) when installing from GitHub (default: main).
- `LCZ4R_GITHUB_REPO`: override GitHub repo (default `ByMaxAnjos/LCZ4r`).
- `LCZ4R_FORCE_REINSTALL`: set to TRUE to force reinstallation even if installed.
- `GT_USE_EXACT`     : `TRUE`/`FALSE` for exact polygons first (default TRUE).
- `GT_MANUAL_BBOX`   : comma separated xmin,xmax,ymin,ymax to override region.

Example:
```r
Sys.setenv(GT_MANUAL_BBOX = "9.90,10.50,36.60,37.20")
source("setup_and_run.R")
```

## Output

Primary output raster: `LCZ4r_output/lcz_map_greater_tunis.tif` plus ROI geopackage and component rasters if produced by LCZ4r functions.

## License

MIT (script only; LCZ4r retains its own license).
