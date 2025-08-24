#!/usr/bin/env Rscript
# Surface Temperature Map from Landsat (uses get_landsat_stack)
source('scripts/common.R')
library(terra)

message('Starting: surface_temperature_map')
stk <- get_landsat_stack()
if (is.null(stk)) stop('No landsat stack available; run scripts/landsat_scene_prep.R or provide preprocessed scenes in output/landsat_scenes or input/LANDSAT/scenes')

lst <- grep('ST_B10', names(stk), value=TRUE)
out_dir <- file.path('output', 'surface_temperature')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
if (length(lst)) {
  # Convert DN to Celsius (Landsat 8/9 scaling)
  temp <- stk[[lst[1]]] * 0.00341802 + 149.0 - 273.15
  out_tif <- file.path(out_dir, 'surface_temperature_map.tif')
  out_png <- file.path(out_dir, 'surface_temperature_map.png')
  writeRaster(temp, out_tif, overwrite=TRUE)
  png(out_png); plot(temp, main='Surface Temperature (°C)'); dev.off()
  message('Wrote raster: ', out_tif)
  message('Wrote PNG:    ', out_png)
  message('Finished: surface_temperature_map')
} else {
  message('No ST_B10 band found in stack.')
  message('Finished: surface_temperature_map (no output)')
}
