#!/usr/bin/env Rscript
# MODIS Land Surface Temperature (LST) Day/Night median composites
# - Looks for MODIS LST files under input/MODIS/ or MODIS/
# - Supports GeoTIFF exports or HDF subdatasets (if GDAL supports HDF)
# - Scales according to MOD11A1/MYD11A1 convention (scale=0.02 K)
# - Converts to Celsius and writes median composites for Day and Night
# - Crops/masks outputs to the ROI used elsewhere (build_roi from scripts/common.R)

suppressPackageStartupMessages({
  library(terra)
  library(tools)
  library(sf)
})
source('scripts/common.R')

message('Starting: modis_lst_map')
out_dir <- file.path('output','modis_lst')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

"# Discover files"
cand_dirs <- c(file.path('input','MODIS'), 'MODIS', file.path('input','modis'))
files <- character()
for (d in cand_dirs) if (dir.exists(d)) files <- c(files, list.files(d, recursive = TRUE, full.names = TRUE))

if (length(files) == 0) stop('No MODIS files found. Place MODIS LST files under input/MODIS or MODIS/.')

# Helper: identify LST Day/Night in filenames (for GeoTIFF fallback)
is_day <- function(x) grepl('LST_Day|LST_Day_1km|_Day_', x, ignore.case = TRUE)
is_night <- function(x) grepl('LST_Night|LST_Night_1km|_Night_', x, ignore.case = TRUE)

# Scale/convert a SpatRaster already loaded
scale_lst_celsius <- function(r) {
  if (is.null(r)) return(NULL)
  # MODIS LST scale factor 0.02 K per unit; invalids often 0
  r <- clamp(r, 0, Inf)
  r * 0.02 - 273.15
}

# Load from path (GeoTIFF or similar), then scale
read_scale_celsius_from_path <- function(path) {
  r <- try(rast(path), silent = TRUE)
  if (inherits(r, 'try-error')) return(NULL)
  if (nlyr(r) > 1) r <- r[[1]]
  scale_lst_celsius(r)
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
day_list <- list()
night_list <- list()

# First, parse any HDF/H5 files and extract LST_Day_1km / LST_Night_1km subdatasets
hdf_idx <- grepl('\\.hdf$|\\.h5$', files, ignore.case = TRUE)
if (any(hdf_idx)) {
  hdf_files <- files[hdf_idx]
  for (p in hdf_files) {
    s <- try(sds(p), silent = TRUE)
    if (inherits(s, 'try-error')) next
    s_names <- names(s)
    # Try classic MOD11A1/MYD11A1 names first
    i_day <- grep('LST.*Day.*1km|LST_Day_1km', s_names, ignore.case = TRUE)
    i_night <- grep('LST.*Night.*1km|LST_Night_1km', s_names, ignore.case = TRUE)
    base <- basename(p)
    is_day_file <- grepl('(A1D|A2D|_D\\.)', base, ignore.case = TRUE) # e.g., MOD21A1D or *_D.hdf
    is_night_file <- grepl('(A1N|A2N|_N\\.)', base, ignore.case = TRUE) # e.g., MOD21A1N or *_N.hdf

    picked_day <- FALSE
    picked_night <- FALSE
    if (length(i_day) > 0) {
      r <- try(s[[i_day[1]]], silent = TRUE)
      if (!inherits(r, 'try-error')) {
        r <- scale_lst_celsius(r)
        if (!is.null(r)) { day_list[[length(day_list)+1]] <- r; picked_day <- TRUE }
      }
    }
    if (length(i_night) > 0) {
      r <- try(s[[i_night[1]]], silent = TRUE)
      if (!inherits(r, 'try-error')) {
        r <- scale_lst_celsius(r)
        if (!is.null(r)) { night_list[[length(night_list)+1]] <- r; picked_night <- TRUE }
      }
    }

    # If not picked yet, handle MOD21A1D/N which expose LST_1KM without Day/Night in name
    if (!(picked_day || picked_night)) {
      i_lst_any <- grep('^LST(_.*)?1KM$|^LST(_.*)?$', s_names, ignore.case = TRUE)
      if (length(i_lst_any) > 0) {
        r <- try(s[[i_lst_any[1]]], silent = TRUE)
        if (!inherits(r, 'try-error')) {
          r <- scale_lst_celsius(r)
          if (!is.null(r)) {
            if (is_day_file && !is_night_file) {
              day_list[[length(day_list)+1]] <- r; picked_day <- TRUE
            } else if (is_night_file && !is_day_file) {
              night_list[[length(night_list)+1]] <- r; picked_night <- TRUE
            } else {
              # Unknown; default to day list but note ambiguity
              day_list[[length(day_list)+1]] <- r; picked_day <- TRUE
              message('Ambiguous LST subdataset in ', base, ' (no Day/Night label). Assigned to Day by default.')
            }
          }
        }
      } else {
        # As a final fallback for MOD11A1/MYD11A1, use known indices (1=Day, 5=Night) when available
        if (grepl('MOD11A1|MYD11A1', base, ignore.case = TRUE)) {
          if (!picked_day && length(s) >= 1) {
            r <- try(s[[1]], silent = TRUE)
            if (!inherits(r, 'try-error')) {
              r <- scale_lst_celsius(r)
              if (!is.null(r)) { day_list[[length(day_list)+1]] <- r; picked_day <- TRUE }
            }
          }
          if (!picked_night && length(s) >= 5) {
            r <- try(s[[5]], silent = TRUE)
            if (!inherits(r, 'try-error')) {
              r <- scale_lst_celsius(r)
              if (!is.null(r)) { night_list[[length(night_list)+1]] <- r; picked_night <- TRUE }
            }
          }
          if (!(picked_day || picked_night)) {
            message('No LST subdataset matched in ', base, '. Names: ', paste(s_names, collapse = ', '))
          }
        } else {
          message('No LST subdataset matched in ', base, '. Names: ', paste(s_names, collapse = ', '))
        }
      }
    }
  }
}

# Next, handle non-HDF files (GeoTIFF, etc.) using filename heuristics
non_hdf <- files[!hdf_idx]
if (length(non_hdf) > 0) {
  day_cands <- non_hdf[is_day(non_hdf)]
  night_cands <- non_hdf[is_night(non_hdf)]
  if (length(day_cands) + length(night_cands) == 0) {
    # fallback: generic naming
    day_cands <- non_hdf[grepl('Day', non_hdf, ignore.case = TRUE)]
    night_cands <- non_hdf[grepl('Night', non_hdf, ignore.case = TRUE)]
  }
  if (length(day_cands) > 0) {
    for (p in day_cands) {
      rr <- read_scale_celsius_from_path(p)
      if (!is.null(rr)) day_list[[length(day_list)+1]] <- rr
    }
  }
  if (length(night_cands) > 0) {
    for (p in night_cands) {
      rr <- read_scale_celsius_from_path(p)
      if (!is.null(rr)) night_list[[length(night_list)+1]] <- rr
    }
  }
}

message('Collected: ', length(day_list), ' day layer(s); ', length(night_list), ' night layer(s)')

message('Building medians...')
day_med <- build_median(day_list)
night_med <- build_median(night_list)

# Crop to ROI if medians exist
crop_to_roi <- function(r) {
  if (is.null(r)) return(NULL)
  roi <- build_roi()
  vroi <- vect(roi)
  vroi <- project(vroi, crs(r))
  r2 <- crop(r, vroi)
  mask(r2, vroi)
}

day_med <- crop_to_roi(day_med)
night_med <- crop_to_roi(night_med)

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
