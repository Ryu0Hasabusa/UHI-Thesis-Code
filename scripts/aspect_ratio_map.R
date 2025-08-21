# Aspect Ratio Map from LCZ using lcz_get_parameters()
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
class_ar <- setNames(params$ar, params$class)
aspect_map <- classify(lcz, class_ar)
writeRaster(aspect_map, 'output/aspect_ratio_map.tif', overwrite=TRUE)
png('output/aspect_ratio_map.png'); plot(aspect_map, main='Aspect Ratio (LCZ)'); dev.off()
