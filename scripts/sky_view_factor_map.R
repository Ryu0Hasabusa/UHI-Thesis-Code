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
params <- lcz_get_parameters()
class_svf <- setNames(params$SVFmean, params$class)
svf_map <- classify(lcz, class_svf)
writeRaster(svf_map, 'output/sky_view_factor_map.tif', overwrite=TRUE)
png('output/sky_view_factor_map.png'); plot(svf_map, main='Sky View Factor (LCZ)'); dev.off()
