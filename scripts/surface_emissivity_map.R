#!/usr/bin/env Rscript
# Surface Emissivity Map from Landsat (uses get_landsat_stack)
source('scripts/common.R')
library(terra)

stk <- get_landsat_stack()
if (is.null(stk)) stop('No landsat stack available; run scripts/landsat_scene_prep.R or provide input/LANDSAT/landsat_stack.tif')

emis <- grep('ST_EMIS', names(stk), value=TRUE)
out_dir <- file.path('output', 'surface_emissivity')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
if (length(emis)) {
  emissivity <- stk[[emis[1]]]
  writeRaster(emissivity, file.path(out_dir, 'surface_emissivity_map.tif'), overwrite=TRUE)
  png(file.path(out_dir, 'surface_emissivity_map.png')); plot(emissivity, main='Surface Emissivity'); dev.off()
} else {
  message('No ST_EMIS band found in stack.')
}
# Surface Emissivity Map from Landsat
library(terra)
r <- rast('input/LANDSAT/landsat_stack.tif')
emis <- grep('ST_EMIS', names(r), value=TRUE)
out_dir <- file.path('output', 'surface_emissivity')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
if (length(emis)) {
  emissivity <- r[[emis[1]]]
  writeRaster(emissivity, file.path(out_dir, 'surface_emissivity_map.tif'), overwrite=TRUE)
  png(file.path(out_dir, 'surface_emissivity_map.png')); plot(emissivity, main='Surface Emissivity'); dev.off()
} else {
  message('No ST_EMIS band found in stack.')
}
