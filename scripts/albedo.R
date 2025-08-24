#!/usr/bin/env Rscript
# Minimal albedo from per-band median rasters
# Reads medians from output/landsat_medians/<band>_median.tif and writes albedo outputs.

suppressPackageStartupMessages({
  library(terra)
  library(sf)
})

message('Starting: albedo (median-based)')
out_dir <- file.path('output','albedo')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
med_dir <- file.path('output','landsat_medians')

bands_needed <- c('SR_B2','SR_B4','SR_B5','SR_B6','SR_B7')
median_files <- setNames(file.path(med_dir, paste0(bands_needed, '_median.tif')), bands_needed)
missing <- median_files[!file.exists(median_files)]
if (length(missing) > 0) stop('Missing median files: ', paste(names(missing), collapse=', '), '. Run scripts/landsat_scene_prep.R first.')

# load rasters and align to common reference
rasters <- lapply(median_files, rast)
ref <- rasters[[1]]
for (i in seq_along(rasters)) {
  if (!compareGeom(ref, rasters[[i]], stopOnError = FALSE, crs = TRUE, ext = FALSE, rowcol = FALSE)) {
    rasters[[i]] <- project(rasters[[i]], crs(ref))
  }
  if (!compareGeom(ref, rasters[[i]], stopOnError = FALSE, rowcol = TRUE, crs = FALSE)) {
    rasters[[i]] <- resample(rasters[[i]], ref, method = 'bilinear')
  }
}

# compute albedo using the coefficients from the original script
b2 <- rasters[['SR_B2']]
b4 <- rasters[['SR_B4']]
b5 <- rasters[['SR_B5']]
b6 <- rasters[['SR_B6']]
b7 <- rasters[['SR_B7']]

alb <- 0.356 * b2 + 0.130 * b4 + 0.373 * b5 + 0.085 * b6 + 0.072 * b7 - 0.0018
alb <- clamp(alb, 0, 1)

out_tif <- file.path(out_dir, 'albedo_median_composite.tif')
writeRaster(alb, out_tif, overwrite = TRUE)

# PNG preview for albedo
png(file.path(out_dir, 'albedo_median_composite.png'), width = 1200, height = 1200)
cols <- if (requireNamespace('viridis', quietly = TRUE)) viridis::viridis(100) else rev(terrain.colors(100))
plot(aggregate(alb, fact=10), main='Albedo median composite', col=cols, colNA='white')
dev.off()

message('Wrote median composite: ', out_tif)
message('Finished: albedo')
