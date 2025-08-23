#!/usr/bin/env Rscript
# Surface Temperature Map from Landsat (uses get_landsat_stack)
source('scripts/common.R')
library(terra)

stk <- get_landsat_stack()
if (is.null(stk)) stop('No landsat stack available; run scripts/landsat_scene_prep.R or provide input/LANDSAT/landsat_stack.tif')

lst <- grep('ST_B10', names(stk), value=TRUE)
out_dir <- file.path('output', 'surface_temperature')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
if (length(lst)) {
  # Convert DN to Celsius (Landsat 8/9 scaling)
  temp <- stk[[lst[1]]] * 0.00341802 + 149.0 - 273.15
  writeRaster(temp, file.path(out_dir, 'surface_temperature_map.tif'), overwrite=TRUE)
  png(file.path(out_dir, 'surface_temperature_map.png')); plot(temp, main='Surface Temperature (°C)'); dev.off()
} else {
  message('No ST_B10 band found in stack.')
}
# Surface Temperature Map from Landsat
library(terra)
r <- rast('input/LANDSAT/landsat_stack.tif')
lst <- grep('ST_B10', names(r), value=TRUE)
out_dir <- file.path('output', 'surface_temperature')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
if (length(lst)) {
  # Convert DN to Celsius (Landsat 8/9 scaling)
  temp <- r[[lst[1]]] * 0.00341802 + 149.0 - 273.15
  writeRaster(temp, file.path(out_dir, 'surface_temperature_map.tif'), overwrite=TRUE)
  png(file.path(out_dir, 'surface_temperature_map.png')); plot(temp, main='Surface Temperature (°C)'); dev.off()
} else {
  message('No ST_B10 band found in stack.')
}
