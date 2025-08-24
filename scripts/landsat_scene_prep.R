#!/usr/bin/env Rscript
# Minimal per-scene Landsat preprocessor
# - finds scene files under `Landsat/`
# - crops/masks to `output/greater_tunis_roi.gpkg` (must exist)
# - applies QA mask to SR bands (sets cloudy pixels to NA)
# - writes one preprocessed TIFF per scene under `output/landsat_scenes/`

library(terra)
library(sf)
library(stringr)

out_root <- file.path('output','landsat_scenes')
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

message('Starting: landsat_scene_prep')

roi_path <- file.path('output','greater_tunis_roi.gpkg')
if (!file.exists(roi_path)) stop('ROI file not found: ', roi_path)
roi <- try(st_read(roi_path, quiet = TRUE), silent = TRUE)
if (inherits(roi, 'try-error')) stop('Failed to read ROI: ', roi_path)
roi_v <- try(vect(roi), silent = TRUE)
if (inherits(roi_v, 'try-error')) stop('Failed to convert ROI to SpatVector')

cat('Scanning Landsat folder for TIFs...\n')
tif_files <- list.files('Landsat', pattern='\\.TIF$', recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
if (length(tif_files) == 0) stop('No Landsat TIFFs found under Landsat/')

# Group files per scene by the common prefix (strip band and suffix parts)
scene_ids <- unique(sub('_(SR|QA|ST|QA_RADSAT|SR_QA_AEROSOL|SR_QA|B).*\\.TIF$', '', basename(tif_files), ignore.case = TRUE))
cat('Found', length(scene_ids), 'scenes\n')

# QA bits to treat as cloudy/shadow/snow/cirrus - these are conservative choices
qa_cloud_bits <- function() {
  list(dilated = bitwShiftL(1,1), cloud = bitwShiftL(1,2), shadow = bitwShiftL(1,3), snow = bitwShiftL(1,4))
}

apply_qa_mask <- function(stack, qa_rast) {
  if (is.null(qa_rast)) return(stack)
  bits <- qa_cloud_bits()
  mask <- app(qa_rast, function(x) as.integer((bitwAnd(as.integer(x), bits$dilated) > 0) |
                                               (bitwAnd(as.integer(x), bits$cloud) > 0) |
                                               (bitwAnd(as.integer(x), bits$shadow) > 0) |
                                               (bitwAnd(as.integer(x), bits$snow) > 0)))
  # mask SR bands only (names starting with SR_ or containing 'SR_B')
  sr_idx <- which(grepl('SR_B|SR_', names(stack), ignore.case = TRUE))
  if (length(sr_idx) == 0) return(stack)
  for (i in sr_idx) stack[[i]] <- mask(stack[[i]], mask, maskvalues = 1, updatevalue = NA)
  stack
}

for (sid in scene_ids) {
  matching <- tif_files[grepl(paste0('^', sid), basename(tif_files), ignore.case = TRUE)]
  if (length(matching) == 0) next
  cat('Processing scene:', sid, '\n')
  # prefer SR_B2 as reference if present
  ref_file <- matching[grepl('SR_B2\\.TIF$', matching, ignore.case = TRUE)]
  if (length(ref_file) == 0) ref_file <- matching[1]
  ref <- try(rast(ref_file), silent = TRUE)
  if (inherits(ref, 'try-error')) { cat('  cannot read reference:', ref_file, '\n'); next }
  # crop reference to ROI
  roi_proj <- try(st_transform(roi, crs(ref)), silent = TRUE)
  if (!inherits(roi_proj, 'try-error')) roi_vp <- vect(roi_proj) else roi_vp <- roi_v
  ref_c <- try(crop(ref, ext(roi_vp)), silent = TRUE)
  if (inherits(ref_c, 'try-error')) { cat('  no overlap with ROI, skipping\n'); next }
  ref <- ref_c

  # build a stack of canonical bands available in this scene
  files_present <- basename(matching)
  # prioritize QA_PIXEL for masking
  qa_file <- matching[grepl('QA_PIXEL', files_present, ignore.case = TRUE)]
  qa <- if (length(qa_file) >= 1) try(rast(qa_file[1]), silent = TRUE) else NULL
  if (!is.null(qa) && inherits(qa, 'try-error')) qa <- NULL

  band_rasts <- list()
  band_names <- character()
  for (f in matching) {
    bn <- tools::file_path_sans_ext(basename(f))
    # simple band name extraction
    bn_tag <- toupper(sub('^.*_(SR_B[0-9]+|QA_PIXEL|ST_B[0-9]+|ST_EMIS|ST_QA|QA_RADSAT).*$','\\1', bn))
    r <- try(rast(f), silent = TRUE)
    if (inherits(r, 'try-error')) next
    # align to ref
    if (!compareGeom(ref, r, stopOnError = FALSE, crs = TRUE, ext = FALSE, rowcol = FALSE)) r <- project(r, crs(ref))
    if (!compareGeom(ref, r, stopOnError = FALSE, rowcol = TRUE, crs = FALSE)) r <- resample(r, ref, method = 'bilinear')
    band_rasts[[length(band_rasts)+1]] <- r
    band_names <- c(band_names, bn_tag)
  }
  if (length(band_rasts) == 0) { cat('  no readable bands, skipping\n'); next }
  stack <- try(rast(band_rasts), silent = TRUE)
  if (inherits(stack, 'try-error')) { cat('  failed to build stack\n'); next }
  names(stack) <- make.names(band_names)

  # crop/mask to ROI and apply QA mask
  stack <- try(crop(stack, ext(roi_vp)), silent = TRUE)
  if (!inherits(stack, 'try-error')) stack <- try(mask(stack, roi_vp), silent = TRUE)
  if (!is.null(qa)) {
    # ensure qa is aligned
    if (!compareGeom(ref, qa, stopOnError = FALSE)) qa <- try(resample(qa, ref), silent = TRUE)
    if (!inherits(qa, 'try-error')) stack <- apply_qa_mask(stack, qa)
  }

  out_file <- file.path(out_root, paste0(gsub('[^A-Za-z0-9_]','_', sid),'_prepped.tif'))
  writeRaster(stack, out_file, overwrite = TRUE)
  cat('  wrote', out_file, '\n')
}

cat('Done. Per-scene outputs in', out_root, '\n')
message('Finished: landsat_scene_prep - per-scene outputs in ', out_root)
