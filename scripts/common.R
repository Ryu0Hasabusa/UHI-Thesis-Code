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
  # Also export ROI as GeoJSON for use in GEE Python workflow
  try(sf::st_write(roi, file.path("output", "greater_tunis_roi.geojson"), delete_dsn = TRUE, quiet = TRUE), silent = TRUE)
  png_file <- file.path("output", "lcz_map_greater_tunis.png")
  png(png_file, width=1000, height=800)
  terra::plot(lcz_byte, col = cols, main = "Greater Tunis LCZ", axes = FALSE)
  plot(sf::st_geometry(roi), add = TRUE, border = 'cyan', lwd = 2)
  dev.off()
  message("Saved: ", ras_file, "; ROI: ", roi_file, "; PNG: ", png_file)
  invisible(list(raster = ras_file, roi = roi_file, png = png_file))
}

download_latest_modis <- function(roi) {
  if (!requireNamespace("MODIStsp", quietly = TRUE)) stop("MODIStsp not installed. Run setup.R first.")
  user <- Sys.getenv("EARTHDATA_USER", unset = "")
  pass <- Sys.getenv("EARTHDATA_PASS", unset = "")
  if (!nzchar(user) || !nzchar(pass)) stop("EARTHDATA_USER/PASS not set.")
  bb <- sf::st_bbox(roi)
  max_days_back <- 7
  base_date <- as.Date(Sys.time(), tz = "UTC") - 1
  sel_date <- NULL
  out_dir <- file.path("output", "MODIS", "MOD11A1")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in 0:max_days_back) {
    d <- base_date - i
    sel_date <- format(d, "%Y.%m.%d")
    message("Trying MOD11A1 date ", sel_date, "…")
    ok <- try(MODIStsp::MODIStsp(gui = FALSE,
                                  out_folder = out_dir,
                                  out_folder_mod = out_dir,
                                  selprod = "MOD11A1.061",
                                  bandsel = c("LST_Day_1km","LST_Night_1km"),
                                  user = user,
                                  password = pass,
                                  start_date = sel_date,
                                  end_date = sel_date,
                                  spatmeth = "bbox",
                                  bbox = c(bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]),
                                  out_format = "GTiff",
                                  compress = "LZW",
                                  resampling = "bilinear",
                                  reprocess = FALSE,
                                  n_retries = 1), silent = TRUE)
    if (!inherits(ok, "try-error")) { message("Success for date ", sel_date); break } else { sel_date <- NULL }
  }
  if (is.null(sel_date)) { warning("Failed to download MOD11A1 for recent dates."); return(invisible(NULL)) }
  tifs <- list.files(out_dir, pattern = "MOD11A1.*LST_(Day|Night).*\\.tif$", full.names = TRUE)
  if (length(tifs)) {
    message("Downloaded MODIS LST files:\n", paste(basename(tifs), collapse = "\n"))
    try({
      rlist <- lapply(tifs, terra::rast)
      stk <- terra::rast(rlist)
      terra::writeRaster(stk, file.path(out_dir, paste0("LST_stack_", gsub("\\.", "_", sel_date), ".tif")), overwrite = TRUE)
    }, silent = TRUE)
  }
  invisible(tifs)
}

## STAC-based downloader removed per user request (was download_latest_landsat). M2M-only flow now.
