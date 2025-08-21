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
params <- lcz_get_parameters()
class_ah <- setNames(params$AHmean, params$class)
ah_map <- classify(lcz, class_ah)
writeRaster(ah_map, 'output/anthropogenic_heat_map.tif', overwrite=TRUE)
png('output/anthropogenic_heat_map.png'); plot(ah_map, main='Anthropogenic Heat (LCZ)'); dev.off()
