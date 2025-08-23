#!/usr/bin/env Rscript
# Compute albedo per-scene and a temporal median composite for a given ROI.
#
# Usage: run from repository root with Rscript:
#   Rscript scripts/albedo.R
#
# Outputs (written to `output/albedo`):
# - per-scene albedo rasters: albedo_scene_<sceneid>.tif
# - median composite: albedo_median_composite.tif
# - observation count raster: albedo_obs_count.tif
# - PNG previews: albedo_median_composite.png, albedo_obs_count.png
#
# Notes:
# - The script looks for Landsat scene files under `Landsat/` with band filenames
#   containing `SR_B2`, `SR_B4`, `SR_B5`, `SR_B6`, `SR_B7` and `QA_PIXEL`.
# - If `output/greater_tunis_roi.gpkg` exists it will crop processing to that ROI.
#

library(terra)

out_dir <- "output/albedo"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("== Albedo builder (temporal composite) ==\n")

# Use preprocessed per-scene stacks created by scripts/landsat_scene_prep.R
scene_dir <- file.path('input','LANDSAT','scenes')
scene_files <- list.files(scene_dir, pattern = '_preproc\\.tif$', full.names = TRUE)
if (length(scene_files) == 0) stop('No preprocessed scene files found in input/LANDSAT/scenes/. Run scripts/landsat_scene_prep.R first.')
cat('Found', length(scene_files), 'preprocessed scene files\n')

# QA bit definitions (Landsat Collection 2 QA_PIXEL)
cloud_bit  <- as.integer(bitwShiftL(1, 5))
shadow_bit <- as.integer(bitwShiftL(1, 3))
snow_bit   <- as.integer(bitwShiftL(1, 4))
cirrus_bit <- as.integer(bitwShiftL(1, 9))

scale_sr <- function(x) x * 0.0000275 - 0.2

per_scene_albedo <- character()
scene_count <- 0

# Load ROI vector if available; fall back to LCZ raster mask if present
roi_vect <- NULL
if (file.exists("output/greater_tunis_roi.gpkg")) {
  try({ roi_vect <- vect("output/greater_tunis_roi.gpkg") }, silent = TRUE)
} else if (file.exists("output/lcz_map_greater_tunis.tif")) {
  try({ lczr <- rast("output/lcz_map_greater_tunis.tif"); roi_vect <- as.polygons(!is.na(lczr)) }, silent = TRUE)
}
if (!is.null(roi_vect)) message('Using ROI for per-scene cropping')

for (sf in scene_files) {
  sid <- tools::file_path_sans_ext(basename(sf))
  cat('Processing preprocessed scene:', sid, '\n')
  s <- rast(sf)
  # expect band order: SR_B2, SR_B4, SR_B5, SR_B6, SR_B7, QA_PIXEL
  if (!all(c('SR_B2','SR_B4','SR_B5','SR_B6','SR_B7','QA_PIXEL') %in% names(s))) {
    warning('Preprocessed scene missing expected bands, skipping: ', sf)
    next
  }
  b2 <- s[['SR_B2']]; b4 <- s[['SR_B4']]; b5 <- s[['SR_B5']]; b6 <- s[['SR_B6']]; b7 <- s[['SR_B7']]; qa <- s[['QA_PIXEL']]
  # compute albedo
  b2r <- scale_sr(b2); b4r <- scale_sr(b4); b5r <- scale_sr(b5); b6r <- scale_sr(b6); b7r <- scale_sr(b7)
  alb <- 0.356 * b2r + 0.130 * b4r + 0.373 * b5r + 0.085 * b6r + 0.072 * b7r - 0.0018
  # QA mask already applied during preprocessing but double-check
  badmask <- app(qa, fun = function(x) as.integer((bitwAnd(as.integer(x), cloud_bit) != 0) |
                                                   (bitwAnd(as.integer(x), shadow_bit) != 0) |
                                                   (bitwAnd(as.integer(x), snow_bit) != 0) |
                                                   (bitwAnd(as.integer(x), cirrus_bit) != 0)))
  alb[badmask == 1] <- NA
  alb <- clamp(alb, 0, 1)
  out_scene <- file.path(out_dir, paste0('albedo_scene_', gsub('[^A-Za-z0-9_]', '_', sid), '.tif'))
  if (file.exists(out_scene)) { cat('Per-scene albedo exists, skipping:', out_scene, '\n'); per_scene_albedo <- c(per_scene_albedo, out_scene); scene_count <- scene_count + 1; next }
  writeRaster(alb, out_scene, overwrite = TRUE)
  per_scene_albedo <- c(per_scene_albedo, out_scene)
  scene_count <- scene_count + 1
}

cat('Created', scene_count, 'per-scene albedo rasters\n')
if (scene_count == 0) stop('No per-scene albedo rasters created; aborting composite')

# Stack aligned per-scene rasters and compute median composite + obs count
stack_files <- per_scene_albedo
if (length(stack_files) == 0) stop('No per-scene albedo files to stack')
ref <- rast(stack_files[[1]])
aligned <- list()
for (f in stack_files) {
  r <- rast(f)
  if (!compareGeom(ref, r, stopOnError = FALSE, crs = TRUE, ext = FALSE, rowcol = FALSE)) r <- project(r, crs(ref))
  if (!compareGeom(ref, r, stopOnError = FALSE, rowcol = TRUE, crs = FALSE)) r <- resample(r, ref, method = 'bilinear')
  aligned <- c(aligned, r)
}
cat('Stacking', length(aligned), 'albedo scenes; computing median composite...\n')
rstack <- rast(aligned)
median_alb <- app(rstack, fun = function(v) median(v, na.rm = TRUE))
writeRaster(median_alb, file.path(out_dir, 'albedo_median_composite.tif'), overwrite = TRUE)
obs_count <- app(rstack, fun = function(v) sum(!is.na(v)))
writeRaster(obs_count, file.path(out_dir, 'albedo_obs_count.tif'), overwrite = TRUE)

# PNG previews
png(file.path(out_dir, 'albedo_median_composite.png'), width = 1200, height = 1200)
cols <- if (requireNamespace('viridis', quietly = TRUE)) viridis::viridis(100) else rev(terrain.colors(100))
plot(aggregate(median_alb, fact=10), main='Albedo median composite', col=cols, colNA='white')
dev.off()
png(file.path(out_dir, 'albedo_obs_count.png'), width = 800, height = 800)
plot(aggregate(obs_count, fact=10), main='Albedo observation count', col=terrain.colors(20))
dev.off()

cat('Temporal composite complete. Outputs in', out_dir, '\n')
