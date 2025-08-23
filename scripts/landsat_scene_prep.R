#!/usr/bin/env Rscript
# Prepare per-scene Landsat stacks: crop first, include canonical bands, align/resample to a reference,
# apply QA masking to SR_ bands only, and build a median landsat_stack.tif.
library(terra)

# prefer GDAL/terra multithreading
Sys.setenv(GDAL_NUM_THREADS = 'ALL_CPUS')
terraOptions(memfrac = 0.6)

out_root <- 'input/LANDSAT/scenes'
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

cat('== Landsat per-scene preprocessor ==\n')

# Load ROI (prefer vector), fallback to LCZ raster mask
roi_vect <- NULL
if (file.exists('output/greater_tunis_roi.gpkg')) {
  try({ roi_vect <- vect('output/greater_tunis_roi.gpkg') }, silent = TRUE)
} else if (file.exists('output/lcz_map_greater_tunis.tif')) {
  try({ lczr <- rast('output/lcz_map_greater_tunis.tif'); roi_vect <- as.polygons(!is.na(lczr)) }, silent = TRUE)
}
if (is.null(roi_vect)) stop('ROI not found; run LCZ generation first (generate LCZ map)')

# Find scene files under Landsat/
tif_files <- list.files('Landsat', pattern='\\.TIF$', recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
if (length(tif_files) == 0) stop('No Landsat TIFFs found under Landsat/')

# scene id extraction: strip common suffixes to group per-scene files
scene_ids <- unique(sub('_(SR|QA|ST|QA_RADSAT|SR_QA_AEROSOL|SR_QA|B).*\\.TIF$', '', basename(tif_files), ignore.case = TRUE))
cat('Found', length(scene_ids), 'scenes to consider\n')

# QA bits
cloud_bit  <- as.integer(bitwShiftL(1, 5))
shadow_bit <- as.integer(bitwShiftL(1, 3))
snow_bit   <- as.integer(bitwShiftL(1, 4))
cirrus_bit <- as.integer(bitwShiftL(1, 9))

# canonical bands to always include (in this order)
# reduced to the user's requested subset
canonical_bands <- c(
  'QA_PIXEL','QA_RADSAT','SR_B1','SR_B2','SR_B3','SR_B4','SR_B5','SR_B6','SR_B7',
  'ST_B10','ST_EMIS','ST_QA'
)

processed_files <- character()
for (sid in scene_ids) {
  matching <- tif_files[grepl(paste0('^', sid), basename(tif_files), ignore.case = TRUE)]
  if (length(matching) == 0) next

  out_file <- file.path(out_root, paste0(gsub('[^A-Za-z0-9_]','_', sid), '_preproc.tif'))
  if (file.exists(out_file)) { cat('Preprocessed exists, skipping:', out_file, '\n'); processed_files <- c(processed_files, out_file); next }
  cat('Preprocessing scene:', sid, '\n')

  # choose a spatial reference raster: prefer SR_B2 if available, otherwise the first file
  ref_file <- matching[grepl('SR_B2\\.TIF$', matching, ignore.case = TRUE)]
  if (length(ref_file) == 0) ref_file <- matching[1]
  ref <- try(rast(ref_file), silent = TRUE)
  if (inherits(ref, 'try-error')) { cat('Cannot read reference for', sid, '\n'); next }
  # crop reference to ROI first to reduce IO/resampling work
  rv <- roi_vect
  if (!is.na(crs(ref)) && !is.na(crs(rv)) && crs(ref) != crs(rv)) rv_ref <- project(rv, crs(ref)) else rv_ref <- rv
  ref_cropped <- try(crop(ref, ext(rv_ref)), silent = TRUE)
  if (inherits(ref_cropped, 'try-error')) {
    cat('Reference has no overlap with ROI, skipping:', sid, '\n'); next
  }
  ref <- ref_cropped

  # prepare list of layers for canonical bands
  layers <- list()
  layer_names <- character()
  for (bn in canonical_bands) {
    fmatch <- matching[grepl(bn, basename(matching), ignore.case = TRUE)]
    if (length(fmatch) >= 1) {
      r <- try(rast(fmatch[[1]]), silent = TRUE)
      if (inherits(r, 'try-error')) {
        nl <- ref[[1]] * NA
        layers <- c(layers, list(nl)); layer_names <- c(layer_names, bn); next
      }
      rv_file <- rv
      if (!is.na(crs(r)) && !is.na(crs(rv_file)) && crs(r) != crs(rv_file)) rv_file <- try(project(rv_file, crs(r)), silent = TRUE)
      if (inherits(rv_file, 'try-error')) rv_file <- rv
      r_cropped <- try(crop(r, ext(rv_file)), silent = TRUE)
      if (inherits(r_cropped, 'try-error')) {
        nl <- ref[[1]] * NA
        layers <- c(layers, list(nl)); layer_names <- c(layer_names, bn); next
      }
      r <- r_cropped
      if (!compareGeom(ref, r, stopOnError = FALSE, crs = TRUE, ext = FALSE, rowcol = FALSE)) r <- project(r, crs(ref))
      if (!compareGeom(ref, r, stopOnError = FALSE, rowcol = TRUE, crs = FALSE)) r <- resample(r, ref, method = 'bilinear')

      if (nlyr(r) == 1) {
        layers <- c(layers, list(r)); layer_names <- c(layer_names, bn)
      } else {
        ln <- names(r)
        idx <- which(grepl(bn, ln, ignore.case = TRUE))
        if (length(idx)) {
          layers <- c(layers, list(r[[idx[1]]]))
          layer_names <- c(layer_names, bn)
        } else {
          layers <- c(layers, list(r[[1]])); layer_names <- c(layer_names, bn)
        }
      }
    } else {
      nl <- ref[[1]] * NA
      layers <- c(layers, list(nl)); layer_names <- c(layer_names, bn)
    }
  }

  stack <- rast(layers)
  names(stack) <- layer_names

  rv <- roi_vect
  if (!is.na(crs(stack)) && !is.na(crs(rv)) && crs(stack) != crs(rv)) rv <- project(rv, crs(stack))
  stack <- try(crop(stack, ext(rv)), silent = TRUE)
  if (!inherits(stack, 'try-error')) stack <- try(mask(stack, rv), silent = TRUE)

  if ('QA_PIXEL' %in% names(stack)) {
    qa <- stack[['QA_PIXEL']]
    if (!all(is.na(values(qa)))) {
      badmask <- app(qa, fun = function(x) as.integer((bitwAnd(as.integer(x), cloud_bit) != 0) |
                                                       (bitwAnd(as.integer(x), shadow_bit) != 0) |
                                                       (bitwAnd(as.integer(x), snow_bit) != 0) |
                                                       (bitwAnd(as.integer(x), cirrus_bit) != 0)))
      sr_idx <- which(tolower(names(stack)) %in% tolower(c('SR_B1','SR_B2','SR_B3','SR_B4','SR_B5','SR_B6','SR_B7')))
      if (length(sr_idx)) {
        for (i in sr_idx) stack[[i]][badmask == 1] <- NA
      }
    }
  }

  writeRaster(stack, out_file, overwrite = TRUE)
  cat('Wrote preprocessed scene:', out_file, '\n')
  processed_files <- c(processed_files, out_file)
}

cat('Preprocessing complete. Preprocessed scenes in', out_root, '\n')

# Build median composite
stack_file <- file.path('input','LANDSAT','landsat_stack.tif')
scene_files <- list.files(out_root, pattern = '_preproc\\.tif$', full.names = TRUE)
if (length(scene_files) == 0) {
  cat('No preprocessed scenes found; skipping median stack build\n')
} else {
  cat('Building median composite from', length(scene_files), 'preprocessed scenes...\n')
  # make scene file paths absolute so worker processes can read them reliably
  scene_files <- normalizePath(scene_files, winslash = '/', mustWork = FALSE)
  ref_file <- scene_files[[1]]
  ref <- rast(ref_file)

  median_bands <- list()
  cat('Computing per-band medians in parallel (PSOCK cluster)...\n')
  median_band_set <- c('QA_PIXEL','QA_RADSAT','SR_B1','SR_B2','SR_B3','SR_B4','SR_B5','SR_B6','SR_B7',
  'ST_B10','ST_EMIS','ST_QA')

  # build list of file paths per band using normalized name matching (robust to punctuation/case)
  norm_name <- function(x) tolower(gsub('[^a-z0-9]', '', x))
  band_files <- lapply(canonical_bands, function(x) character())
  names(band_files) <- canonical_bands
  for (sf in scene_files) {
    r <- try(rast(sf), silent = TRUE)
    if (inherits(r, 'try-error')) next
    ln_norm <- norm_name(names(r))
    for (bn in canonical_bands) {
      if (any(ln_norm == norm_name(bn))) band_files[[bn]] <- c(band_files[[bn]], sf)
    }
  }

  library(parallel)
  cores <- max(1, parallel::detectCores(logical = FALSE) - 1)
  # Try a larger worker count first (6), then fall back to smaller counts to avoid IO/GDAL contention
  max_try <- min(6, cores, length(canonical_bands))
  # Only attempt the computed max_try workers (no smaller fallbacks)
  try_list <- max_try
  cat('Will attempt parallel runs with workers:', paste(try_list, collapse = ', '), '\n')
  # ensure band_files contains absolute paths
  band_files <- lapply(band_files, function(xs) if (length(xs)) normalizePath(xs, winslash = '/', mustWork = FALSE) else xs)
  project_dir <- normalizePath(getwd(), winslash = '/')

  # helper to run parLapply with safe start/stop
  run_with_workers <- function(w) {
    cat(' - attempting', w, 'workers (cores avail:', parallel::detectCores(), ')\n')
    cl <- NULL
    res <- NULL
    success <- FALSE
    tryCatch({
      cl <- makeCluster(w)
      clusterExport(cl, c('band_files','median_band_set','canonical_bands','ref_file','project_dir','norm_name'), envir = environment())
      clusterEvalQ(cl, { setwd(project_dir); Sys.setenv(GDAL_NUM_THREADS = 'ALL_CPUS'); library(terra) })
      res <- parLapply(cl, canonical_bands, band_job)
      success <- TRUE
    }, error = function(e) {
      cat('  parallel error:', e$message, '\n')
    }, finally = {
      try({ if (!is.null(cl)) stopCluster(cl) }, silent = TRUE)
    })
    if (!isTRUE(success) || is.null(res)) return(list(success=FALSE, results=NULL)) else return(list(success=TRUE, results=res))
  }
  band_job <- function(bn) {
    tryCatch({
      ref <- rast(ref_file)
      fpaths <- unique(band_files[[bn]])
      n <- length(fpaths)
      if (n == 0) return(list(bn=bn, tmp=NA, n=0))
      if (!(bn %in% median_band_set)) {
        r <- rast(fpaths[1]); idx <- grep(bn, names(r), ignore.case = TRUE)[1]
        layer <- if (!is.na(idx)) r[[idx]] else r[[1]]
        tmpf <- file.path('input','LANDSAT','tmp_median', paste0('median_', bn, '_', Sys.getpid(), '_', sample(1e6,1), '.tif'))
        dir.create(dirname(tmpf), recursive = TRUE, showWarnings = FALSE)
        writeRaster(layer, tmpf, overwrite = TRUE)
        return(list(bn=bn, tmp=tmpf, n=1))
      }
      layers <- lapply(fpaths, function(sf) {
        rr <- rast(sf)
        # robust selection by normalized layer names
        ln_idx <- which(norm_name(names(rr)) == norm_name(bn))[1]
        if (is.na(ln_idx)) {
          # fallback to case-insensitive grep
          ln_idx <- grep(bn, names(rr), ignore.case = TRUE)[1]
        }
        if (is.na(ln_idx)) return(NULL)
        ly <- rr[[ln_idx]]
        if (!compareGeom(ref, ly, stopOnError = FALSE, crs = TRUE, ext = FALSE, rowcol = FALSE)) ly <- project(ly, crs(ref))
        if (!compareGeom(ref, ly, stopOnError = FALSE, rowcol = TRUE, crs = FALSE)) ly <- resample(ly, ref, method = 'bilinear')
        ly
      })
      layers <- Filter(Negate(is.null), layers)
      if (length(layers) == 0) return(list(bn=bn, tmp=NA, n=0))
      if (length(layers) == 1) {
        tmpf <- file.path('input','LANDSAT','tmp_median', paste0('median_', bn, '_', Sys.getpid(), '_', sample(1e6,1), '.tif'))
        dir.create(dirname(tmpf), recursive = TRUE, showWarnings = FALSE)
        writeRaster(layers[[1]], tmpf, overwrite = TRUE)
        return(list(bn=bn, tmp=tmpf, n=1))
      }
      tmpf <- file.path('input','LANDSAT','tmp_median', paste0('median_', bn, '_', Sys.getpid(), '_', sample(1e6,1), '.tif'))
      dir.create(dirname(tmpf), recursive = TRUE, showWarnings = FALSE)
      # Accumulate per-block medians into a full-length vector to avoid writeStart/writeValues issues
      nrows_tot <- nrow(ref)
      ncols_tot <- ncol(ref)
      ncell_tot <- nrows_tot * ncols_tot
      out_vec <- rep(NA_real_, ncell_tot)
      block_rows <- min(256, nrows_tot)
      for (row_start in seq(1, nrows_tot, by = block_rows)) {
        nrows_block <- min(block_rows, nrows_tot - row_start + 1)
        vals_block <- lapply(layers, function(ly) {
          rv <- try(readValues(ly, row = row_start, nrows = nrows_block), silent = TRUE)
          if (inherits(rv, 'try-error')) return(rep(NA_real_, ncols_tot * nrows_block))
          as.numeric(rv)
        })
        if (length(vals_block) == 0) {
          med_block <- rep(NA_real_, ncols_tot * nrows_block)
        } else {
          mat <- do.call(cbind, vals_block)
          if (ncol(mat) == 1) {
            med_block <- as.numeric(mat)
          } else {
            if (requireNamespace('matrixStats', quietly = TRUE)) {
              med_block <- matrixStats::rowMedians(mat, na.rm = TRUE)
            } else {
              med_block <- apply(mat, 1, median, na.rm = TRUE)
            }
          }
        }
        # write into output vector (terra stores rows sequentially)
        start_idx <- (row_start - 1) * ncols_tot + 1
        end_idx <- start_idx + length(med_block) - 1
        out_vec[start_idx:end_idx] <- med_block
      }
      # write final raster from vector
      out_r <- ref[[1]]
      out_r <- setValues(out_r, out_vec)
      writeRaster(out_r, tmpf, overwrite = TRUE)
      if (!file.exists(tmpf)) return(list(bn=bn, tmp=NA, n=length(layers)))
      return(list(bn=bn, tmp=tmpf, n=length(layers)))
    }, error = function(e) list(bn=bn, tmp=NA, n=0))
  }

  # attempt parallel runs with fallback sizes
  results <- NULL
  for (w in try_list) {
    out <- run_with_workers(w)
    if (isTRUE(out$success)) { results <- out$results; break }
    cat(' - parallel attempt with', w, 'workers failed; trying smaller count\n')
  }
  if (is.null(results)) stop('All parallel attempts failed; aborting median build')

  for (res in results) {
    bn <- res$bn
    if (is.null(res$tmp) || is.na(res$tmp)) median_bands[[bn]] <- ref[[1]] * NA else median_bands[[bn]] <- rast(res$tmp)
    cat(' - band', bn, '->', ifelse(is.null(res$n), 0, res$n), 'layers processed\n')
  }

  cat('Assembling median stack...\n')
  median_stack <- try(rast(median_bands), silent = TRUE)
  if (inherits(median_stack, 'try-error')) stop('Failed to assemble median stack')
  names(median_stack) <- canonical_bands
  dir.create(dirname(stack_file), recursive = TRUE, showWarnings = FALSE)
  writeRaster(median_stack, stack_file, overwrite = TRUE)
  cat('Wrote median stack to', stack_file, '\n')
}
