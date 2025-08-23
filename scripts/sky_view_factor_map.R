source("scripts/common.R")
# Sky View Factor Map from LCZ using lcz_get_parameters()
library(terra)
library(LCZ4r)
lcz_file <- 'output/lcz_map_greater_tunis.tif'
if (!file.exists(lcz_file)) {
  message('LCZ raster not found. Generating with lcz_get_map() ...')
  roi <- build_roi()
  lcz <- lcz_get_map(roi = roi, isave_map = TRUE)
} else {
  lcz <- rast(lcz_file)
}
params <- lcz_get_parameters(lcz)
svf_mean <- params[["SVFmean"]]
if (!dir.exists("output/sky_view_factor")) dir.create("output/sky_view_factor", recursive = TRUE)
writeRaster(svf_mean, "output/sky_view_factor/sky_view_factor_mean_map.tif", overwrite=TRUE)
plot(svf_mean, main="Sky View Factor (Mean, LCZ)")
png(file.path("output", "sky_view_factor", "sky_view_factor_mean_map.png")); plot(svf_mean, main="Sky View Factor (Mean, LCZ)"); dev.off()
