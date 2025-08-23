source("scripts/common.R")
# Anthropogenic Heat Map from LCZ using lcz_get_parameters()
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
ah_mean <- params[["AHmean"]]
if (!dir.exists("output/anthropogenic_heat")) dir.create("output/anthropogenic_heat", recursive = TRUE)
writeRaster(ah_mean, "output/anthropogenic_heat/anthropogenic_heat_mean_map.tif", overwrite=TRUE)
plot(ah_mean, main="Anthropogenic Heat (Mean, LCZ)")
png(file.path("output","anthropogenic_heat","anthropogenic_heat_mean_map.png")); plot(ah_mean, main="Anthropogenic Heat (Mean, LCZ)"); dev.off()
