#!/usr/bin/env Rscript
# Vegetation Fraction Map from NDVI (uses get_landsat_stack from common.R)
source('scripts/common.R')
library(terra)

stk <- get_landsat_stack()
if (is.null(stk)) stop('No landsat stack available; run scripts/landsat_scene_prep.R or provide input/LANDSAT/landsat_stack.tif')

out_dir <- file.path('output', 'vegetation_fraction')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

if (all(c('SR_B4','SR_B5') %in% names(stk))) {
  ndvi <- (stk[['SR_B5']] - stk[['SR_B4']]) / (stk[['SR_B5']] + stk[['SR_B4']])
  # Assumes QA masking has been applied during preprocessing (landsat_scene_prep.R)
  writeRaster(ndvi, file.path(out_dir, 'vegetation_fraction_map.tif'), overwrite=TRUE)
  png(file.path(out_dir, 'vegetation_fraction_map.png')); plot(ndvi, main='Vegetation Fraction (NDVI)'); dev.off()
} else {
  message('SR_B4 or SR_B5 band not found in stack.')
}
