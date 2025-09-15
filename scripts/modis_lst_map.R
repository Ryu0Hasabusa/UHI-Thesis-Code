#!/usr/bin/env Rscript
# MODIS Land Surface Temperature (LST) Day/Night median composites
# - Looks for MODIS LST files under input/MODIS/ or MODIS/
# - Supports GeoTIFF exports or HDF subdatasets (if GDAL supports HDF)
# - Scales according to MOD11A1/MYD11A1 convention (scale=0.02 K)
# - Converts to Celsius and writes median composites for Day and Night

suppressPackageStartupMessages({
  library(terra)
  library(tools)
})

message('Starting: modis_lst_map')
out_dir <- file.path('output','modis_lst')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# Discover files
cand_dirs <- c(file.path('input','MODIS'), 'MODIS', file.path('input','modis'))
files <- character()
for (d in cand_dirs) if (dir.exists(d)) files <- c(files, list.files(d, recursive = TRUE, full.names = TRUE))

if (length(files) == 0) stop('No MODIS files found. Place MODIS LST files under input/MODIS or MODIS/.')

# Helper: identify LST Day/Night bands
is_day <- function(x) grepl('LST_Day|LST_Day_1km|_Day_', x, ignore.case = TRUE)
is_night <- function(x) grepl('LST_Night|LST_Night_1km|_Night_', x, ignore.case = TRUE)

# If HDF, try to resolve subdatasets via GDAL-style syntax if needed
expand_hdf <- function(path) {
  ext <- tolower(file_ext(path))
  if (ext %in% c('hdf','h5')) {
    # terra can often read via gdal subdataset index if provided
    # Here we return the original path; downstream we try vector of subdatasets if needed
    return(path)
  }
  path
}

files <- vapply(files, expand_hdf, character(1))

# Filter candidates
day_cands <- files[is_day(files)]
night_cands <- files[is_night(files)]

if (length(day_cands) + length(night_cands) == 0) {
  # fallback: try generic naming
  day_cands <- files[grepl('Day', files, ignore.case = TRUE)]
  night_cands <- files[grepl('Night', files, ignore.case = TRUE)]
}

message('Found: ', length(day_cands), ' day files; ', length(night_cands), ' night files')

read_scale_celsius <- function(path) {
  r <- try(rast(path), silent = TRUE)
  if (inherits(r, 'try-error')) return(NULL)
  # If multi-layer, pick first layer heuristically
  if (nlyr(r) > 1) r <- r[[1]]
  # MODIS LST scale factor 0.02 K per unit; invalids often 0
  r <- clamp(r, 0, Inf)
  r <- r * 0.02 - 273.15
  r
}

read_many <- function(paths) {
  rs <- list()
  for (p in paths) {
    rr <- read_scale_celsius(p)
    if (!is.null(rr)) rs[[length(rs)+1]] <- rr
  }
  rs
}

build_median <- function(lst) {
  if (length(lst) == 0) return(NULL)
  # align to the first as reference
  ref <- lst[[1]]
  aligned <- vector('list', length(lst))
  for (i in seq_along(lst)) {
    x <- lst[[i]]
    if (!compareGeom(ref, x, stopOnError = FALSE, rowcol = TRUE, crs = TRUE, ext = TRUE)) {
      x <- try(resample(project(x, crs(ref)), ref, method = 'bilinear'), silent = TRUE)
      if (inherits(x, 'try-error')) next
    }
    aligned[[i]] <- x
  }
  aligned <- Filter(Negate(is.null), aligned)
  if (length(aligned) == 0) return(NULL)
  st <- rast(aligned)
  app(st, median, na.rm = TRUE)
}

# Read and composite
message('Reading day files...')
day_list <- read_many(day_cands)
message('Reading night files...')
night_list <- read_many(night_cands)

message('Building medians...')
day_med <- build_median(day_list)
night_med <- build_median(night_list)

# Write outputs
if (!is.null(day_med)) {
  out_day_tif <- file.path(out_dir, 'modis_lst_day_median_celsius.tif')
  writeRaster(day_med, out_day_tif, overwrite = TRUE)
  png(file.path(out_dir, 'modis_lst_day_median_celsius.png'))
  plot(day_med, main = 'MODIS LST Day (Median, °C)')
  dev.off()
  # CSV
  df <- as.data.frame(day_med, xy = TRUE, cells = FALSE, na.rm = TRUE)
  names(df) <- c('x','y','lst_day_c')
  write.csv(df, file.path(out_dir, 'modis_lst_day_median_celsius.csv'), row.names = FALSE)
  message('Wrote: ', out_day_tif)
} else {
  message('No valid Day LST rasters to composite.')
}

if (!is.null(night_med)) {
  out_night_tif <- file.path(out_dir, 'modis_lst_night_median_celsius.tif')
  writeRaster(night_med, out_night_tif, overwrite = TRUE)
  png(file.path(out_dir, 'modis_lst_night_median_celsius.png'))
  plot(night_med, main = 'MODIS LST Night (Median, °C)')
  dev.off()
  # CSV
  df <- as.data.frame(night_med, xy = TRUE, cells = FALSE, na.rm = TRUE)
  names(df) <- c('x','y','lst_night_c')
  write.csv(df, file.path(out_dir, 'modis_lst_night_median_celsius.csv'), row.names = FALSE)
  message('Wrote: ', out_night_tif)
} else {
  message('No valid Night LST rasters to composite.')
}

message('Finished: modis_lst_map')
