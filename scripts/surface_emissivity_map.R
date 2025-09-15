#!/usr/bin/env Rscript
# Surface Emissivity Map from Landsat (uses get_landsat_stack)
source('scripts/common.R')
library(terra)

message('Starting: surface_emissivity_map')

out_dir <- file.path('output', 'surface_emissivity')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# prefer precomputed median
med_file <- file.path('output','landsat_medians','ST_EMIS_median.tif')
if (file.exists(med_file)) {
  emissivity <- rast(med_file)
} else {
  stop(sprintf('Missing median file: %s. Run scripts/landsat_scene_prep.R to generate it.', med_file))
}

out_tif <- file.path(out_dir, 'surface_emissivity_map.tif')
out_png <- file.path(out_dir, 'surface_emissivity_map.png')
writeRaster(emissivity, out_tif, overwrite=TRUE)
png(out_png); plot(emissivity, main='Surface Emissivity'); dev.off()
# CSV export (hardcoded)
emis_df <- as.data.frame(emissivity, xy = TRUE, cells = FALSE, na.rm = TRUE)
names(emis_df) <- c('x','y','emissivity')
write.csv(emis_df, file.path(out_dir, 'surface_emissivity_map.csv'), row.names = FALSE)
message('Wrote raster: ', out_tif)
message('Wrote PNG:    ', out_png)
message('Finished: surface_emissivity_map')
