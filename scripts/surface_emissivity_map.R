#!/usr/bin/env Rscript
# Surface Emissivity Map from Landsat (uses get_landsat_stack)
source('scripts/common.R')
library(terra)

message('Starting: surface_emissivity_map')
stk <- get_landsat_stack()
if (is.null(stk)) stop('No landsat stack available; run scripts/landsat_scene_prep.R or provide preprocessed scenes in output/landsat_scenes or input/LANDSAT/scenes')

emis <- grep('ST_EMIS', names(stk), value=TRUE)
out_dir <- file.path('output', 'surface_emissivity')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
if (length(emis)) {
  emissivity <- stk[[emis[1]]]
  out_tif <- file.path(out_dir, 'surface_emissivity_map.tif')
  out_png <- file.path(out_dir, 'surface_emissivity_map.png')
  writeRaster(emissivity, out_tif, overwrite=TRUE)
  png(out_png); plot(emissivity, main='Surface Emissivity'); dev.off()
  message('Wrote raster: ', out_tif)
  message('Wrote PNG:    ', out_png)
  message('Finished: surface_emissivity_map')
} else {
  message('No ST_EMIS band found in stack.')
  message('Finished: surface_emissivity_map (no output)')
}
