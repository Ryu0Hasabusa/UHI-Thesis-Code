# Vegetation Fraction Map from NDVI
library(terra)
r <- rast('input/LANDSAT/landsat_stack.tif')
b4 <- grep('SR_B4', names(r), value=TRUE)
b5 <- grep('SR_B5', names(r), value=TRUE)
if (length(b4) && length(b5)) {
  ndvi <- (r[[b5]] - r[[b4]]) / (r[[b5]] + r[[b4]])
  writeRaster(ndvi, 'output/vegetation_fraction_map.tif', overwrite=TRUE)
  png('output/vegetation_fraction_map.png'); plot(ndvi, main='Vegetation Fraction (NDVI)'); dev.off()
} else {
  message('SR_B4 or SR_B5 band not found in stack.')
}
