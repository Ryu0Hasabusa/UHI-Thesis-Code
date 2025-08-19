#!/usr/bin/env Rscript
# Run: Generate LCZ map + latest Landsat (low-cloud) scene
source("scripts/common.R")
message("== Run: LCZ + Landsat ==")
roi <- build_roi()
generate_lcz_map(roi)
download_latest_landsat(roi)
message("Done.")
