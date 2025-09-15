source("scripts/common.R")
# Tree Surface Fraction (TSF) Map from LCZ using lcz_get_parameters()
library(terra)
library(LCZ4r)
message('Starting: tree_surface_fraction_map')
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
tsf_mean <- params[["TSFmean"]]
if (!dir.exists("output/tree_surface_fraction")) dir.create("output/tree_surface_fraction", recursive = TRUE)
out_dir <- file.path("output","tree_surface_fraction")
out_tif <- file.path(out_dir, "tree_surface_fraction_mean_map.tif")
writeRaster(tsf_mean, out_tif, overwrite=TRUE)
png(file.path(out_dir, "tree_surface_fraction_mean_map.png")); plot(tsf_mean, main="Tree Surface Fraction (Mean, LCZ) [%]"); dev.off()
# CSV export (hardcoded)
tsf_df <- as.data.frame(tsf_mean, xy = TRUE, cells = FALSE, na.rm = TRUE)
names(tsf_df) <- c("x","y","TSFmean")
write.csv(tsf_df, file.path(out_dir, "tree_surface_fraction_mean_map.csv"), row.names = FALSE)
message('Wrote raster: ', out_tif)
message('Finished: tree_surface_fraction_map')
