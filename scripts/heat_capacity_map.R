source("scripts/common.R")
# Heat Capacity/Surface Admittance Map from LCZ using lcz_get_parameters()
library(terra)
library(LCZ4r)
message('Starting: heat_capacity_map')
lcz_file <- 'output/lcz_map_greater_tunis.tif'
if (!file.exists(lcz_file)) {
  message('LCZ raster not found. Generating with lcz_get_map() ...')
  roi <- build_roi()
  lcz <- lcz_get_map(roi = roi, isave_map = TRUE)
} else {
  lcz <- rast(lcz_file)
}
params <- lcz_get_parameters(lcz)
hc_mean <- params[["SADmean"]]
if (!dir.exists("output/heat_capacity")) dir.create("output/heat_capacity", recursive = TRUE)
out_tif <- file.path("output","heat_capacity","heat_capacity_mean_map.tif")
writeRaster(hc_mean, out_tif, overwrite=TRUE)
png(file.path("output","heat_capacity","heat_capacity_mean_map.png")); plot(hc_mean, main="Heat Capacity/Surface Admittance (Mean, LCZ)"); dev.off()
message('Wrote raster: ', out_tif)
message('Finished: heat_capacity_map')
