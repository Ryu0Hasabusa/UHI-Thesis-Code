#!/usr/bin/env Rscript
# Simple entry: generate LCZ map + latest MOD11A1 (MODIS)
Sys.setenv(ENABLE_MODIS = "TRUE", ENABLE_LANDSAT = "FALSE")
# Optional: set EARTHDATA_USER and EARTHDATA_PASS before calling this script
source("scripts/setup_and_run.R")
