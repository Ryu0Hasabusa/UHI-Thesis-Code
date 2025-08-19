#!/usr/bin/env Rscript
# Simple entry: generate LCZ map + latest Landsat low-cloud scene
Sys.setenv(ENABLE_MODIS = "FALSE", ENABLE_LANDSAT = "TRUE")
# Optional: override LANDSAT_* env vars before calling this script
source("scripts/setup_and_run.R")
