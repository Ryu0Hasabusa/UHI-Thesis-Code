source("scripts/common.R")
# Sky View Factor Map from LCZ using lcz_get_parameters()
library(terra)
library(LCZ4r)
message('Starting: sky_view_factor_map')
lcz_file <- 'output/lcz_map_greater_tunis.tif'
if (!file.exists(lcz_file)) {
  message('LCZ raster not found. Generating with lcz_get_map() ...')
  roi <- build_roi()
  generate_lcz_map(roi)
} else {
  lcz <- rast(lcz_file)
}
params <- lcz_get_parameters(lcz)
svf_mean <- params[["SVFmean"]]
if (!dir.exists("output/sky_view_factor")) dir.create("output/sky_view_factor", recursive = TRUE)
out_tif <- file.path("output", "sky_view_factor", "sky_view_factor_mean_map.tif")
writeRaster(svf_mean, out_tif, overwrite=TRUE)
png(file.path("output", "sky_view_factor", "sky_view_factor_mean_map.png")); plot(svf_mean, main="Sky View Factor (Mean, LCZ)"); dev.off()
message('Wrote raster: ', out_tif)
message('Finished: sky_view_factor_map')
