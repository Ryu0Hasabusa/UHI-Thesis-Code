source("scripts/common.R")
# Anthropogenic Heat Map from LCZ using lcz_get_parameters()
library(terra)
library(LCZ4r)
message('Starting: anthropogenic_heat_map')
lcz_file <- 'output/lcz_map_greater_tunis.tif'
if (!file.exists(lcz_file)) {
  message('LCZ raster not found. Generating with lcz_get_map() ...')
  roi <- build_roi()
  lcz <- lcz_get_map(roi = roi, isave_map = TRUE)
  lcz <- rast(lcz_file)
} else {
  lcz <- rast(lcz_file)
}
params <- lcz_get_parameters(lcz)
ah_mean <- params[["AHmean"]]
if (!dir.exists("output/anthropogenic_heat")) dir.create("output/anthropogenic_heat", recursive = TRUE)
out_tif <- file.path("output","anthropogenic_heat","anthropogenic_heat_mean_map.tif")
writeRaster(ah_mean, out_tif, overwrite=TRUE)
png(file.path("output","anthropogenic_heat","anthropogenic_heat_mean_map.png")); plot(ah_mean, main="Anthropogenic Heat (Mean, LCZ)"); dev.off()
# CSV export (hardcoded)
ah_df <- as.data.frame(ah_mean, xy = TRUE, cells = FALSE, na.rm = TRUE)
names(ah_df) <- c("x","y","AHmean")
write.csv(ah_df, file.path("output","anthropogenic_heat","anthropogenic_heat_mean_map.csv"), row.names = FALSE)
message('Wrote raster: ', out_tif)
message('Finished: anthropogenic_heat_map')
