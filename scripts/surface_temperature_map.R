# Surface Temperature Map from Landsat
library(terra)
r <- rast('input/LANDSAT/landsat_stack.tif')
lst <- grep('ST_B10', names(r), value=TRUE)
if (length(lst)) {
  # Convert DN to Celsius (Landsat 8/9 scaling)
  temp <- r[[lst[1]]] * 0.00341802 + 149.0 - 273.15
  writeRaster(temp, 'output/surface_temperature_map.tif', overwrite=TRUE)
  png('output/surface_temperature_map.png'); plot(temp, main='Surface Temperature (°C)'); dev.off()
} else {
  message('No ST_B10 band found in stack.')
}
