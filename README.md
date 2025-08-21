# UHI-Thesis-Code

This repository contains only the essential scripts for generating Local Climate Zone (LCZ) maps and processing Landsat data for Greater Tunis. All obsolete files, MODIS workflows, and extra documentation have been removed as of August 2025.

## Structure
- **scripts/**: All code for ROI setup, LCZ mapping, Landsat processing, and urban metrics
- **scripts/common.R**: Centralized config and helper functions
- **scripts/run_lcz_landsat.R**: Processes user-supplied Landsat stack (manual input only)
- **scripts/[metric]_map.R**: Aspect ratio, SVF, albedo, NDVI, NDBI, NDWI, and other metrics (auto-generates LCZ raster if missing)
- **scripts/roi_config.json**: ROI and config overrides
- **Landsat/**: Place your Landsat files here. Each subfolder should be named with the path and row number (e.g., `191034` for path 191, row 034).

## Usage
1. Install R dependencies:
   ```powershell
   Rscript scripts/setup.R
   ```
2. Process Landsat stack:
   - Place your Landsat files inside the `Landsat/` folder.
   - Each Landsat subfolder should be named with the path and row number (e.g., `191034` for path 191, row 034).
   - Run:
   ```powershell
   Rscript scripts/run_lcz_landsat.R
   ```
3. Run metric scripts as needed:
   ```powershell
   Rscript scripts/aspect_ratio_map.R
   Rscript scripts/sky_view_factor_map.R
   # ...other metric scripts
   ```

When you run the scripts, the `input/` and `output/` folders will be created automatically if they do not exist.

## License
See `LCZ4r/LICENSE` for LCZ4r package license. All other scripts are MIT unless otherwise stated.
