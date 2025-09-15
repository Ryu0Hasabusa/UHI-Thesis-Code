source("scripts/common.R")
# Impervious Surface Fraction Map (LCZ-derived)
library(terra)
library(LCZ4r)
message('Starting: impervious_surface_map')
lcz_file <- 'output/lcz_map_greater_tunis.tif'
if (!file.exists(lcz_file)) {
  message('LCZ raster not found. Generating with lcz_get_map() ...')
  roi <- build_roi()
  generate_lcz_map(roi)
} else {
  lcz <- rast(lcz_file)
}
params <- lcz_get_parameters(lcz)
isf_mean <- params[["ISFmean"]]
if (!dir.exists("output/impervious_surface")) dir.create("output/impervious_surface", recursive = TRUE)
out_tif <- file.path("output", "impervious_surface", "impervious_surface_mean_map.tif")
writeRaster(isf_mean, out_tif, overwrite=TRUE)
png(file.path("output", "impervious_surface", "impervious_surface_mean_map.png")); plot(isf_mean, main="Impervious Surface Fraction (Mean, LCZ)"); dev.off()
message('Wrote raster: ', out_tif)
message('Finished: impervious_surface_map')
