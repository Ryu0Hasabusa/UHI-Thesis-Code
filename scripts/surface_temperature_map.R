#!/usr/bin/env Rscript
# Surface Temperature Map from Landsat (uses get_landsat_stack)
source('scripts/common.R')
library(terra)

message('Starting: surface_temperature_map')

out_dir <- file.path('output', 'surface_temperature')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# prefer precomputed median
med_file <- file.path('output','landsat_medians','ST_B10_median.tif')
med_file <- file.path('output','landsat_medians','ST_B10_median.tif')
if (file.exists(med_file)) {
  st <- rast(med_file)
} else {
  stop(sprintf('Missing median file: %s. Run scripts/landsat_scene_prep.R to generate it.', med_file))
}

# Convert DN/K to Celsius (Landsat scaling assumed applied in preprocessing)
temp <- st - 273.15
out_tif <- file.path(out_dir, 'surface_temperature_map.tif')
out_png <- file.path(out_dir, 'surface_temperature_map.png')
writeRaster(temp, out_tif, overwrite=TRUE)
png(out_png); plot(temp, main='Surface Temperature (°C)'); dev.off()
message('Wrote raster: ', out_tif)
message('Wrote PNG:    ', out_png)
message('Finished: surface_temperature_map')
