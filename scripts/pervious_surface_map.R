source("scripts/common.R")
# Pervious (Vegetation) Surface Fraction Map (LCZ-derived)
library(terra)
library(LCZ4r)
message('Starting: pervious_surface_map')
lcz_file <- 'output/lcz_map_greater_tunis.tif'
if (!file.exists(lcz_file)) {
  message('LCZ raster not found. Generating with lcz_get_map() ...')
  roi <- build_roi()
  generate_lcz_map(roi)
  lcz <- rast(lcz_file)
} else {
  lcz <- rast(lcz_file)
}
params <- lcz_get_parameters(lcz)
psf_mean <- params[["PSFmean"]]
if (!dir.exists("output/pervious_surface")) dir.create("output/pervious_surface", recursive = TRUE)
out_tif <- file.path("output", "pervious_surface", "pervious_surface_mean_map.tif")
writeRaster(psf_mean, out_tif, overwrite=TRUE)
png(file.path("output", "pervious_surface", "pervious_surface_mean_map.png")); plot(psf_mean, main="Pervious (Vegetation) Surface Fraction (Mean, LCZ)"); dev.off()
# CSV export (hardcoded)
psf_df <- as.data.frame(psf_mean, xy = TRUE, cells = FALSE, na.rm = TRUE)
names(psf_df) <- c("x","y","PSFmean")
write.csv(psf_df, file.path("output", "pervious_surface", "pervious_surface_mean_map.csv"), row.names = FALSE)
message('Wrote raster: ', out_tif)
message('Finished: pervious_surface_map')
