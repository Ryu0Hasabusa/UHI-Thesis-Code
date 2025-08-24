# Common utility functions shared by run scripts (ROI + LCZ + downloads)

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(osmdata)
  library(jsonlite)
  library(LCZ4r)
})
try(sf::sf_use_s2(FALSE), silent = TRUE)

read_roi_config <- function() {
  cfg <- list()
  if (file.exists("scripts/roi_config.json")) {
    cfg <- tryCatch(jsonlite::read_json("scripts/roi_config.json"), error = function(e) list())
  }
  cfg
}

cfg_get <- function(key, default=NULL, cfg=read_roi_config()) {
  envv <- Sys.getenv(toupper(key), unset = NA)
  if (!is.na(envv) && nzchar(envv)) return(envv)
  if (!is.null(cfg[[key]])) return(cfg[[key]])
  default
}

build_roi <- function() {
  cfg <- read_roi_config()
  use_exact <- tolower(cfg_get("GT_USE_EXACT", "TRUE", cfg)) %in% c("true","t","1","yes","y")
  manual_bbox_raw <- cfg_get("GT_MANUAL_BBOX", "", cfg)
  manual_bbox <- NULL
  if (length(manual_bbox_raw) == 1 && nzchar(manual_bbox_raw)) {
    parts <- strsplit(manual_bbox_raw, "[,; ]+")[[1]]
    if (length(parts) == 4) manual_bbox <- suppressWarnings(as.numeric(parts))
    if (any(is.na(manual_bbox))) stop("Invalid GT_MANUAL_BBOX config.")
  }
  names_list <- c("Tunis Governorate", "Ariana Governorate", "Ben Arous Governorate", "Manouba Governorate")
  get_poly <- function(nm) {
    if (use_exact) {
      poly_obj <- try(getbb(nm, format_out = "sf_polygon", limit = 1), silent = TRUE)
      if (!inherits(poly_obj, "try-error") && !is.null(poly_obj)) {
        g <- poly_obj$geometry; if (is.null(g)) g <- poly_obj$multipolygon; if (is.null(g)) g <- poly_obj$polygon
        if (!is.null(g)) {
          sfpoly <- sf::st_as_sf(g) |> sf::st_make_valid()
          return(sfpoly)
        }
      }
      message("Exact polygon failed for ", nm, "; using bbox.")
    }
    bb <- try(getbb(nm, format_out = "matrix", limit = 1), silent = TRUE)
    if (inherits(bb, "try-error") || is.null(bb)) stop("No boundary for ", nm)
    sf::st_polygon(list(rbind(
      c(bb[1,1], bb[2,1]), c(bb[1,2], bb[2,1]), c(bb[1,2], bb[2,2]), c(bb[1,1], bb[2,2]), c(bb[1,1], bb[2,1])
    ))) |> sf::st_sfc(crs=4326) |> sf::st_as_sf()
  }
  if (!is.null(manual_bbox)) {
    message("Using manual bbox override.")
    bb <- manual_bbox
    roi <- sf::st_polygon(list(rbind(
      c(bb[1],bb[3]), c(bb[2],bb[3]), c(bb[2],bb[4]), c(bb[1],bb[4]), c(bb[1],bb[3])
    ))) |> sf::st_sfc(crs=4326) |> sf::st_as_sf()
  } else {
    polys <- lapply(names_list, function(nm) tryCatch(get_poly(nm), error = function(e) { message("Failed ", nm, ": ", e$message); NULL }))
    polys <- Filter(Negate(is.null), polys)
    if (!length(polys)) stop("Could not build any polygons.")
    geoms <- lapply(polys, sf::st_geometry)
    polys_sf <- sf::st_as_sf(do.call(c, geoms))
    roi <- sf::st_union(polys_sf) |> sf::st_as_sf() |> sf::st_make_valid()
  }
  bb <- sf::st_bbox(roi)
  message("ROI bbox: lon [", signif(bb[["xmin"]],4), ", ", signif(bb[["xmax"]],4), "] lat [", signif(bb[["ymin"]],4), ", ", signif(bb[["ymax"]],4), "]")
  roi
}

generate_lcz_map <- function(roi) {
  message("Generating LCZ map…")
  lcz <- lcz_get_map(roi = roi, isave_map = FALSE)
  cols <- c(
    "#910613", "#D9081C", "#FF0A22", "#C54F1E", "#FF6628", "#FF985E",
    "#FDED3F", "#BBBBBB", "#FFCBAB", "#565656", "#006A18", "#00A926",
    "#628432", "#B5DA7F", "#000000", "#FCF7B1", "#656BFA"
  )
  ct <- as.data.frame(t(col2rgb(cols)))
  names(ct) <- c("red","green","blue")
  ct <- cbind(value = 1:17, ct, alpha = 255)
  lcz_byte <- lcz
  terra::coltab(lcz_byte, 1) <- ct
  if (!dir.exists("output")) dir.create("output", recursive = TRUE)
  ras_file <- file.path("output", "lcz_map_greater_tunis.tif")
  roi_file <- file.path("output", "greater_tunis_roi.gpkg")
  terra::writeRaster(lcz_byte, ras_file, datatype = "INT1U", overwrite = TRUE)
  try(sf::st_write(roi, roi_file, delete_dsn = TRUE, quiet = TRUE), silent = TRUE)
  # Legacy: previously exported ROI GeoJSON for GEE automation (removed); keeping export optional if needed later
  try(sf::st_write(roi, file.path("output", "greater_tunis_roi.geojson"), delete_dsn = TRUE, quiet = TRUE), silent = TRUE)
  png_file <- file.path("output", "lcz_map_greater_tunis.png")
  png(png_file, width=1000, height=800)
  terra::plot(lcz_byte, col = cols, main = "Greater Tunis LCZ", axes = FALSE)
  plot(sf::st_geometry(roi), add = TRUE, border = 'cyan', lwd = 2)
  dev.off()
  message("Saved: ", ras_file, "; ROI: ", roi_file, "; PNG: ", png_file)
  invisible(list(raster = ras_file, roi = roi_file, png = png_file))
}

## Helper: return a Landsat stack SpatRaster.
## Priority: if file input/LANDSAT/landsat_stack.tif exists, use it.
## Otherwise, if preprocessed per-scene stacks exist in input/LANDSAT/scenes/, build a median composite per band.
get_landsat_stack <- function(write_if_missing = TRUE) {
  stack_file <- file.path('input','LANDSAT','landsat_stack.tif')
  if (file.exists(stack_file)) return(rast(stack_file))

  # prefer preprocessed per-scene stacks under output/landsat_scenes, fall back to input/LANDSAT/scenes
  possible_dirs <- c(file.path('output','landsat_scenes'), file.path('input','LANDSAT','scenes'))
  scene_files <- character()
  for (d in possible_dirs) {
    if (dir.exists(d)) {
      sf <- list.files(d, pattern = '_preproc\\.tif$|_prepped\\.tif$', full.names = TRUE)
      if (length(sf) > 0) { scene_files <- sf; break }
    }
  }
  if (length(scene_files) == 0) return(NULL)
  if (length(scene_files) == 0) return(NULL)

  # expected band names (include thermal bands used elsewhere)
  band_names <- c('SR_B2','SR_B4','SR_B5','SR_B6','SR_B7','ST_B10','ST_EMIS','QA_PIXEL')

  # scale/offset metadata for bands (from Landsat metadata table)
  # reflectance: value * scale + offset
  scale_map <- list(
    SR_B1 = list(scale = 2.75e-05, offset = -0.2),
    SR_B2 = list(scale = 2.75e-05, offset = -0.2),
    SR_B3 = list(scale = 2.75e-05, offset = -0.2),
    SR_B4 = list(scale = 2.75e-05, offset = -0.2),
    SR_B5 = list(scale = 2.75e-05, offset = -0.2),
    SR_B6 = list(scale = 2.75e-05, offset = -0.2),
    SR_B7 = list(scale = 2.75e-05, offset = -0.2),
    ST_B10 = list(scale = 0.00341802, offset = 149),
    ST_EMIS = list(scale = 0.0001, offset = 0)
  )

  # reference grid = first valid scene
  ref <- rast(scene_files[[1]])

  # collect per-band layers across scenes
  scenes_by_band <- lapply(band_names, function(x) list())
  names(scenes_by_band) <- band_names

  for (sf in scene_files) {
    r <- try(rast(sf), silent = TRUE)
    if (inherits(r, 'try-error')) next
    if (!all(band_names %in% names(r))) next
    # apply band-specific scale/offset where available (skip QA_PIXEL and bitmasks)
    for (bn in intersect(names(r), names(scale_map))) {
      s <- scale_map[[bn]]
      # defensive: only apply if scale is numeric
      if (!is.null(s$scale) && is.numeric(s$scale)) {
        r[[bn]] <- r[[bn]] * s$scale
      }
      if (!is.null(s$offset) && is.numeric(s$offset) && s$offset != 0) {
        r[[bn]] <- r[[bn]] + s$offset
      }
    }
    # align CRS and resolution to reference
    if (!compareGeom(ref, r, stopOnError = FALSE, crs = TRUE, ext = FALSE, rowcol = FALSE)) r <- project(r, crs(ref))
    if (!compareGeom(ref, r, stopOnError = FALSE, rowcol = TRUE, crs = FALSE)) r <- resample(r, ref, method = 'bilinear')
    for (bn in band_names) {
      scenes_by_band[[bn]] <- c(scenes_by_band[[bn]], list(r[[bn]]))
    }
  }

  # if no valid scenes collected, abort
  if (all(sapply(scenes_by_band, length) == 0)) return(NULL)

  # compute median for SR bands and thermal bands; for QA produce NA layer
  median_bands <- list()
  # compute for all bands except the final QA_PIXEL
  compute_names <- band_names[band_names != 'QA_PIXEL']
  for (bn in compute_names) {
    layers <- scenes_by_band[[bn]]
    if (length(layers) == 0) {
      median_bands[[bn]] <- ref[[1]]*NA
    } else {
      multi <- do.call(c, layers)
      median_bands[[bn]] <- app(multi, fun = function(v) median(v, na.rm = TRUE))
    }
  }
  median_stack <- rast(median_bands)
  names(median_stack) <- compute_names

  qa_blank <- median_stack[[1]] * NA
  names(qa_blank) <- 'QA_PIXEL'
  full_stack <- c(median_stack, qa_blank)

  if (write_if_missing) {
    dir.create(dirname(stack_file), recursive = TRUE, showWarnings = FALSE)
    writeRaster(full_stack, stack_file, overwrite = TRUE)
  }
  full_stack
}

