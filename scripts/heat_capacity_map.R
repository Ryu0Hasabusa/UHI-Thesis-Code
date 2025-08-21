# Heat Capacity/Surface Admittance Map from LCZ using lcz_get_parameters()
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
class_hc <- setNames(params$SADmean, params$class)
hc_map <- classify(lcz, class_hc)
writeRaster(hc_map, 'output/heat_capacity_map.tif', overwrite=TRUE)
png('output/heat_capacity_map.png'); plot(hc_map, main='Heat Capacity/Surface Admittance (LCZ)'); dev.off()
