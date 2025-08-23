# UHI-Thesis-Code

Essential scripts for generating Local Climate Zone (LCZ) maps and processing Landsat data for Greater Tunis.

## Requirements
- R (from CRAN)
- The repository provides `scripts/setup.R` to install R package dependencies. The setup script installs packages including `terra`, `sf`, and `elevatr` (the latter is used to fetch a DEM if none is available locally).

Install dependencies:
```powershell
Rscript scripts/setup.R
```

Note: fetching a DEM with `elevatr` requires network access and the `sf` package.

## Project structure (important files)
- `scripts/` — main scripts for ROI, LCZ mapping, Landsat preprocessing, and metrics.
  - `scripts/common.R` — shared helpers (includes `get_landsat_stack()` and `build_roi()`).
  - `scripts/landsat_scene_prep.R` — per-scene Landsat preprocessing (crop → align → canonical band stack) and median composite builder.
    - Writes per-scene outputs to `input/LANDSAT/scenes/<scene>_preproc.tif`.
    - Writes median composite to `input/LANDSAT/landsat_stack.tif`.
  - `scripts/solar_radiation_map.R` — computes a relative annual solar exposure raster; attempts to fetch a DEM with `elevatr` when no local DEM is found. Writes output to `output/solar_radiation/`.
  - `scripts/albedo.R` — albedo workflow (per-scene albedo and temporal median composite) — outputs in `output/albedo/`.
  - Metric scripts (e.g. `aspect_ratio_map.R`, `surface_emissivity_map.R`, `vegetation_fraction_map.R`) that use `get_landsat_stack()` or the median stack at `input/LANDSAT/landsat_stack.tif`.
- `Landsat/` — place raw Landsat TIFFs here (folder structure optional). The preprocessor finds TIFFs recursively under this folder.

## Typical workflow
1. Install dependencies:
```powershell
Rscript scripts/setup.R
```
2. Prepare Landsat inputs:
   - Place original Landsat TIFFs under the `Landsat/` folder (recursive search).
3. Preprocess per-scene stacks and build median composite:
```powershell
Rscript scripts/landsat_scene_prep.R
```
This writes per-scene preprocessed stacks to `input/LANDSAT/scenes/` and a median composite to `input/LANDSAT/landsat_stack.tif`.
4. Run metric scripts (examples):
```powershell
Rscript scripts/solar_radiation_map.R
Rscript scripts/vegetation_fraction_map.R
Rscript scripts/surface_emissivity_map.R
```

## Outputs (examples)
- `input/LANDSAT/scenes/<scene>_preproc.tif` — preprocessed per-scene stacks
- `input/LANDSAT/landsat_stack.tif` — median composite used by metrics
- `output/solar_radiation/solar_radiation_relative_annual.tif` — relative annual solar exposure (0–1)
- `output/albedo/` — albedo outputs (if `scripts/albedo.R` is run)

## DEM behavior
- The solar radiation script looks for a local DEM at `input/DEM/dem.tif` (or a few other common locations). If no DEM is found it will try to fetch one using `elevatr::get_elev_raster()` and the ROI derived from `scripts/common.R::build_roi()` or from the extent of preprocessed scenes. Network access is required to fetch a DEM.

## License
See `LCZ4r/LICENSE` for the LCZ4r package license. Other repository scripts are MIT unless otherwise stated.

If you want, I can also:
- add a short Troubleshooting section (common errors and fixes), or
- make the README more compact and add a `docs/` walkthrough.
