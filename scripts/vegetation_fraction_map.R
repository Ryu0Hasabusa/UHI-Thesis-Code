#!/usr/bin/env Rscript
# Vegetation Fraction Map from NDVI (uses get_landsat_stack from common.R)
source('scripts/common.R')
library(terra)

message('Starting: vegetation_fraction_map')

out_dir <- file.path('output', 'vegetation_fraction')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# prefer precomputed medians
med_dir <- file.path('output','landsat_medians')
b4_file <- file.path(med_dir, 'SR_B4_median.tif')
b5_file <- file.path(med_dir, 'SR_B5_median.tif')
if (file.exists(b4_file) && file.exists(b5_file)) {
  b4 <- rast(b4_file)
  b5 <- rast(b5_file)
} else {
  stop(sprintf('Missing precomputed medians: %s and/or %s. Run scripts/landsat_scene_prep.R to generate per-band medians in output/landsat_medians/', b4_file, b5_file))
}
  denom <- b5 + b4
  # avoid division-by-near-zero: mask pixels where denominator is very small
  eps <- 1e-6
  safe_mask <- abs(denom) > eps
  ndvi <- (b5 - b4) / denom
  ndvi[!safe_mask] <- NA
  # clamp to physical NDVI range [-1, 1]
  ndvi <- clamp(ndvi, -1, 1)
  # Assumes QA masking has been applied during preprocessing (landsat_scene_prep.R)
  out_tif <- file.path(out_dir, 'vegetation_fraction_map.tif')
  out_png <- file.path(out_dir, 'vegetation_fraction_map.png')
writeRaster(ndvi, out_tif, overwrite=TRUE)
png(out_png); plot(ndvi, main='Vegetation Fraction (NDVI)'); dev.off()
# CSV export (hardcoded)
ndvi_df <- as.data.frame(ndvi, xy = TRUE, cells = FALSE, na.rm = TRUE)
names(ndvi_df) <- c('x','y','NDVI')
write.csv(ndvi_df, file.path(out_dir, 'vegetation_fraction_map.csv'), row.names = FALSE)
message('Wrote raster: ', out_tif)
message('Wrote PNG:    ', out_png)
message('Finished: vegetation_fraction_map')
