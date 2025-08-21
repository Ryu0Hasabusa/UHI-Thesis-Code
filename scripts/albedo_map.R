# Albedo Map from Landsat Reflectance
library(terra)
r <- rast('input/LANDSAT/landsat_stack.tif')
# Typical albedo estimation: mean of SR_B2, SR_B3, SR_B4
b2 <- grep('SR_B2', names(r), value=TRUE)
b3 <- grep('SR_B3', names(r), value=TRUE)
b4 <- grep('SR_B4', names(r), value=TRUE)
albedo <- (r[[b2]] + r[[b3]] + r[[b4]]) / 3
writeRaster(albedo, 'output/albedo_map.tif', overwrite=TRUE)
png('output/albedo_map.png'); plot(albedo, main='Albedo (mean SR_B2-4)'); dev.off()
