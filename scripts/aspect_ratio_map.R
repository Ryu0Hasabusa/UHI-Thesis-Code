source("scripts/common.R")
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
params <- lcz_get_parameters(lcz)
# Extract and save aspect ratio rasters
ar_mean <- params[["ARmean"]]
if (!dir.exists("output/aspect_ratio")) dir.create("output/aspect_ratio", recursive = TRUE)
writeRaster(ar_mean, "output/aspect_ratio/aspect_ratio_mean_map.tif", overwrite=TRUE)
plot(ar_mean, main="Aspect Ratio (Mean, LCZ)") 
png(file.path("output", "aspect_ratio", "aspect_ratio_mean_map.png")); plot(ar_mean, main="Aspect Ratio (Mean, LCZ)"); dev.off()