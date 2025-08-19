#!/usr/bin/env Rscript
# Run: Generate LCZ map + latest MODIS LST (needs prior setup + EARTHDATA creds)
source("scripts/common.R")
message("== Run: LCZ + MODIS LST ==")
roi <- build_roi()
generate_lcz_map(roi)
download_latest_modis(roi)
message("Done.")
