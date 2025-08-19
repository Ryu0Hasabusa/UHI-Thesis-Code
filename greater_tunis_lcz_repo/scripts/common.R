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

download_latest_landsat <- function(roi) {
  if (!requireNamespace("rstac", quietly = TRUE)) stop("rstac not installed. Run setup.R first.")
  suppressPackageStartupMessages({ library(rstac) })
  roi <- sf::st_transform(roi, 4326)
  bb <- sf::st_bbox(roi)
  start_default <- format(Sys.Date() - 30, "%Y-%m-%d")
  end_default   <- format(Sys.Date(), "%Y-%m-%d")
  start_date <- Sys.getenv("LANDSAT_START", unset = start_default)
  end_date   <- Sys.getenv("LANDSAT_END",   unset = end_default)
  max_cloud  <- as.numeric(Sys.getenv("LANDSAT_MAX_CLOUD", unset = "10")); if (is.na(max_cloud)) max_cloud <- 10
  bands_req  <- Sys.getenv("LANDSAT_BANDS", unset = "SR_B2,SR_B3,SR_B4,SR_B5,SR_B6,SR_B7,ST_B10,QA_PIXEL")
  bands_req  <- unlist(strsplit(bands_req, "[,; ]+"))
  endpoint <- rstac::stac("https://landsatlook.usgs.gov/stac-server")
  collections <- c("landsat-c2l2-sr")
  search <- rstac::stac_search(endpoint,
                               collections = collections,
                               bbox = c(bb[["xmin"], bb[["ymin"], bb[["xmax"], bb[["ymax"]),
                               datetime = paste0(start_date, "/", end_date),
                               limit = 50,
                               query = list(cloud_cover = paste0("<", max_cloud)))
  items <- try(rstac::items_fetch(search), silent = TRUE)
  if (inherits(items, "try-error")) { warning("Failed to query STAC for Landsat."); return(invisible(NULL)) }
  if (length(items$features) == 0) { warning("No Landsat scenes found within constraints."); return(invisible(NULL)) }
  clouds <- sapply(items$features, function(f) f$properties$cloud_cover)
  idx <- which.min(clouds)
  scene <- items$features[[idx]]
  scene_id <- scene$id
  message("Selected scene: ", scene_id, " cloud_cover=", clouds[idx])
  assets <- scene$assets
  out_dir <- file.path("output", "LANDSAT", scene_id)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  downloaded <- list()
  for (b in bands_req) {
    if (!is.null(assets[[b]])) {
      url <- assets[[b]]$href
      dest <- file.path(out_dir, paste0(scene_id, "_", b, ".tif"))
      if (!file.exists(dest)) {
        message("Downloading ", b, " -> ", dest)
        try(utils::download.file(url, dest, mode = "wb", quiet = TRUE), silent = TRUE)
      }
      if (file.exists(dest)) downloaded[[b]] <- dest
    } else {
      message("Band asset ", b, " not present; skipping.")
    }
  }
  if (length(downloaded)) {
    rlist <- list()
    for (nm in names(downloaded)) {
      rast_obj <- try(terra::rast(downloaded[[nm]]), silent = TRUE)
      if (!inherits(rast_obj, "try-error")) {
        if (grepl("^SR_B", nm)) {
          rast_obj <- rast_obj * 0.0000275 - 0.2
        } else if (nm == "ST_B10") {
          rast_obj <- rast_obj * 0.00341802 + 149.0
          rast_obj <- rast_obj - 273.15
          names(rast_obj) <- "LST_C"
          nm <- "LST_C"
        }
        names(rast_obj) <- nm
        rlist[[nm]] <- rast_obj
      }
    }
    if (length(rlist)) {
      stk <- terra::rast(rlist)
      stk_file <- file.path(out_dir, paste0(scene_id, "_stack.tif"))
      terra::writeRaster(stk, stk_file, overwrite = TRUE)
      message("Wrote Landsat stack: ", stk_file)
    }
  }
  invisible(downloaded)
}
