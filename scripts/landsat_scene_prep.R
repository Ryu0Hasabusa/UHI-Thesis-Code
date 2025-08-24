#!/usr/bin/env Rscript
# Build per-band median composites from per-scene Landsat files.
# For each scene, read QA_PIXEL and the requested bands, mask each band where QA indicates cloud/shadow/snow,
# then compute the median across scenes for each band separately and write per-band median TIFFs under output/landsat_medians/.

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(stringr)
})

out_dir <- file.path('output','landsat_medians')
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message('Starting: landsat_scene_prep (median per-band)')

# ROI is optional here; if present we'll crop to it
roi_path <- file.path('output','greater_tunis_roi.gpkg')
roi_v <- NULL
if (file.exists(roi_path)) {
  roi <- try(sf::st_read(roi_path, quiet = TRUE), silent = TRUE)
  if (!inherits(roi, 'try-error')) roi_v <- try(terra::vect(roi), silent = TRUE)
}

# bands to produce medians for
bands <- c('SR_B2','SR_B4','SR_B5','SR_B6','SR_B7','ST_B10','ST_EMIS')

# helper: QA bits considered cloudy/shadow/snow/cirrus (conservative)
qa_cloud_bits <- function() list(
  dilated = bitwShiftL(1, 1),  # bit 1
  cirrus  = bitwShiftL(1, 2),  # bit 2
  cloud   = bitwShiftL(1, 3),  # bit 3
  shadow  = bitwShiftL(1, 4),  # bit 4
  snow    = bitwShiftL(1, 5)   # bit 5
)

# per-band scale/offset (same values used previously in common.R)
scale_map <- list(
  SR_B2 = list(scale = 0.0000275, offset = -0.2),
  SR_B4 = list(scale = 0.0000275, offset = -0.2),
  SR_B5 = list(scale = 0.0000275, offset = -0.2),
  SR_B6 = list(scale = 0.0000275, offset = -0.2),
  SR_B7 = list(scale = 0.0000275, offset = -0.2),
  ST_B10 = list(scale = 0.00341802, offset = 149),
  ST_EMIS = list(scale = 0.0001, offset = 0)
)

# collect masked rasters per band
masked_by_band <- lapply(bands, function(x) list())
names(masked_by_band) <- bands

## Instead of relying on prepped per-scene multi-band TIFFs, scan the Landsat/ tree
## for individual band files across path/row/date subfolders. For each band, collect
## matching files and treat each as one observation (one date). Use QA_PIXEL files found
## in the same directory (if present) to mask cloudy/snow pixels.

landsat_root <- 'Landsat'
if (!dir.exists(landsat_root)) stop('Landsat directory not found at top-level. Place scene folders under Landsat/<pathrow>/<scene>/')

# list all TIFFs once to speed repeated greps
all_tifs <- list.files(landsat_root, pattern = '\\.(tif|TIF)$', recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
if (length(all_tifs) == 0) stop('No TIFFs found under Landsat/ - ensure your scenes are placed under Landsat/<pathrow>/')

for (bn in bands) {
  # find files whose filename contains the band token (case-insensitive)
  matches <- all_tifs[grepl(bn, basename(all_tifs), ignore.case = TRUE)]
  if (length(matches) == 0) {
    message('Band ', bn, ': no files found under Landsat/ - skipping')
    next
  }
  message('Band ', bn, ': found ', length(matches), ' files (dates/pathrows)')

  # per-band reference geometry (use first successfully-read file)
  ref_band <- NULL
  for (mf in matches) {
    r <- try(terra::rast(mf), silent = TRUE)
    if (inherits(r, 'try-error')) next
    # single-layer expected; if multi-layer, take first
    band_r <- r[[1]]

    # optionally crop to ROI — reproject ROI to the raster CRS first to ensure alignment
    if (!is.null(roi_v) && inherits(roi_v, 'SpatVector')) {
      try({
        roi_proj <- roi_v
        # if CRS differs, project the ROI to the raster's CRS
        r_crs <- try(terra::crs(band_r), silent = TRUE)
        roi_crs <- try(terra::crs(roi_proj), silent = TRUE)
        if (!inherits(r_crs, 'try-error') && !inherits(roi_crs, 'try-error') && !is.na(r_crs) && !is.na(roi_crs) && r_crs != roi_crs) {
          roi_proj <- terra::project(roi_proj, r_crs)
        }
        band_r <- terra::crop(band_r, terra::ext(roi_proj))
        band_r <- terra::mask(band_r, roi_proj)
      }, silent = TRUE)
    }

    # find QA_PIXEL in same directory matching this band's scene (path/row/date)
    qa <- NULL
    base <- basename(mf)
    # prefix = filename up to just before the band token (case-insensitive)
    prefix <- sub(paste0('(?i)', bn, '.*$'), '', base, perl = TRUE)
    # look for QA_PIXEL files that start with the same prefix and contain QA_PIXEL
    qa_pattern <- paste0('^', prefix, '.*QA_PIXEL.*\\.tif$')
    qa_candidates <- list.files(dirname(mf), pattern = qa_pattern, full.names = TRUE, ignore.case = TRUE)
    # fallback to any QA_PIXEL tif in the same directory
    if (length(qa_candidates) == 0) {
      qa_candidates <- list.files(dirname(mf), pattern = 'QA_PIXEL.*\\.tif$', full.names = TRUE, ignore.case = TRUE)
    }
    if (length(qa_candidates) > 0) {
      qf <- try(terra::rast(qa_candidates[1]), silent = TRUE)
      if (!inherits(qf, 'try-error')) qa <- qf[[1]]
    }

    # apply scale/offset when present
    if (bn %in% names(scale_map)) {
      s <- scale_map[[bn]]
      if (!is.null(s$scale) && is.numeric(s$scale)) band_r <- band_r * s$scale
      if (!is.null(s$offset) && is.numeric(s$offset) && s$offset != 0) band_r <- band_r + s$offset
    }

    # set per-band reference and resample subsequent rasters to it
    if (is.null(ref_band)) {
      ref_band <- band_r
    } else {
      if (!compareGeom(band_r, ref_band, stopOnError = FALSE)) {
        band_r <- try(terra::resample(band_r, ref_band), silent = TRUE)
        if (inherits(band_r, 'try-error')) next
      }
    }

    # align and apply QA mask if present; failure in masking should NOT skip the band — just continue without mask
    if (!is.null(qa) && !inherits(qa, 'try-error')) {
      safe_mask_result <- try({
        qa2 <- qa
        if (!compareGeom(qa2, ref_band, stopOnError = FALSE)) qa2 <- terra::resample(qa2, ref_band, method = 'near')
        bits <- qa_cloud_bits()
        m <- terra::app(qa2, function(x) as.integer(
          (bitwAnd(as.integer(x), bits$dilated) > 0) |
          (bitwAnd(as.integer(x), bits$cirrus) > 0) |
          (bitwAnd(as.integer(x), bits$cloud) > 0) |
          (bitwAnd(as.integer(x), bits$shadow) > 0) |
          (bitwAnd(as.integer(x), bits$snow) > 0)
        ))
        if (!compareGeom(m, ref_band, stopOnError = FALSE)) m <- terra::resample(m, ref_band, method = 'near')
        band_r <- terra::mask(band_r, m, maskvalues = 1, updatevalue = NA)
        TRUE
      }, silent = TRUE)
      if (inherits(safe_mask_result, 'try-error') || identical(safe_mask_result, FALSE)) {
        message(sprintf('  QA masking failed for %s — continuing without mask', mf))
      }
    }

    masked_by_band[[bn]][[length(masked_by_band[[bn]]) + 1]] <- band_r
  }
}

# compute median per band and write outputs
for (bn in bands) {
  layers <- masked_by_band[[bn]]
  if (length(layers) == 0) {
    message('Band ', bn, ' not found in any scene; skipping')
    next
  }
  message('---')
  message(sprintf('Start: band %s (%d scenes)', bn, length(layers)))
  multi <- try(do.call(c, layers), silent = TRUE)
  if (inherits(multi, 'try-error')) { message('  failed to stack layers for ', bn); next }
  med <- terra::app(multi, fun = function(v) median(v, na.rm = TRUE))
  out_file <- file.path(out_dir, paste0(bn, '_median.tif'))
  terra::writeRaster(med, out_file, overwrite = TRUE)
  message(sprintf('Finished: band %s - wrote %s', bn, out_file))
}

message('Finished: landsat_scene_prep (medians in ', out_dir, ')')
