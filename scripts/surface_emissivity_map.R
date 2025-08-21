# Surface Emissivity Map from Landsat
library(terra)
r <- rast('input/LANDSAT/landsat_stack.tif')
emis <- grep('ST_EMIS', names(r), value=TRUE)
if (length(emis)) {
  emissivity <- r[[emis[1]]]
  writeRaster(emissivity, 'output/surface_emissivity_map.tif', overwrite=TRUE)
  png('output/surface_emissivity_map.png'); plot(emissivity, main='Surface Emissivity'); dev.off()
} else {
  message('No ST_EMIS band found in stack.')
}
