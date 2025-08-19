#!/usr/bin/env Rscript
# Run: Generate LCZ map + latest MODIS LST (needs prior setup + EARTHDATA creds)
# Optional local credential injection (leave blank or edit locally; do NOT commit real creds):
# Sys.setenv(EARTHDATA_USER = "your_username_here")
# Sys.setenv(EARTHDATA_PASS = "your_password_here")
source("scripts/common.R")
message("== Run: LCZ + MODIS LST ==")
roi <- build_roi()
generate_lcz_map(roi)
download_latest_modis(roi)
message("Done.")
