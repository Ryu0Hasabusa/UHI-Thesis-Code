# Fetch latest low-cloud Landsat Collection 2 Level-2 surface reflectance + thermal band via STAC
# Uses rstac (no credentials). Writes files under output/LANDSAT.
# Env vars (optional):
#   LANDSAT_START (default: 30 days before today)
#   LANDSAT_END   (default: today)
#   LANDSAT_MAX_CLOUD (default: 10)
#   LANDSAT_BANDS (comma list, default common set)

suppressPackageStartupMessages({
  library(rstac)
  library(jsonlite)
  library(sf)
  library(terra)
})

roi_path <- "output/greater_tunis_roi.gpkg"
if (!file.exists(roi_path)) stop("ROI file not found for Landsat download.")
roi <- sf::st_read(roi_path, quiet = TRUE)
roi <- sf::st_transform(roi, 4326)
bb <- sf::st_bbox(roi)

start_default <- format(Sys.Date() - 30, "%Y-%m-%d")
end_default   <- format(Sys.Date(), "%Y-%m-%d")
start_date <- Sys.getenv("LANDSAT_START", unset = start_default)
end_date   <- Sys.getenv("LANDSAT_END",   unset = end_default)
max_cloud  <- as.numeric(Sys.getenv("LANDSAT_MAX_CLOUD", unset = "10"))
if (is.na(max_cloud)) max_cloud <- 10
bands_req  <- Sys.getenv("LANDSAT_BANDS", unset = "SR_B2,SR_B3,SR_B4,SR_B5,SR_B6,SR_B7,ST_B10,QA_PIXEL")
bands_req  <- unlist(strsplit(bands_req, "[,; ]+"))

# Landsat STAC endpoint (USGS)
endpoint <- stac("https://landsatlook.usgs.gov/stac-server")
collections <- c("landsat-c2l2-sr")  # surface reflectance. LST in the ST_B10 asset.

search <- stac_search(endpoint,
                      collections = collections,
                      bbox = c(bb[["xmin"], bb[["ymin"], bb[["xmax"], bb[["ymax"]),
                      datetime = paste0(start_date, "/", end_date),
                      limit = 50,
                      query = list(cloud_cover = paste0("<", max_cloud)))

items <- try(items_fetch(search), silent = TRUE)
if (inherits(items, "try-error")) stop("Failed to query STAC for Landsat.")
if (length(items$features) == 0) {
  warning("No Landsat scenes found within constraints.")
} else {
  # Pick scene with minimal cloud_cover property
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
      message("Band asset ", b, " not present in scene; skipping.")
    }
  }
  if (length(downloaded)) {
    # Build stack for reflectance (scale) and thermal (convert to Kelvin -> C optional)
    rlist <- list()
    for (nm in names(downloaded)) {
      rast_obj <- try(terra::rast(downloaded[[nm]]), silent = TRUE)
      if (!inherits(rast_obj, "try-error")) {
        # Apply scale factors for SR & ST_B10
        if (grepl("^SR_B", nm)) {
          rast_obj <- rast_obj * 0.0000275 - 0.2
        } else if (nm == "ST_B10") {
          rast_obj <- rast_obj * 0.00341802 + 149.0  # Kelvin
          kelvin <- rast_obj
          rast_obj <- kelvin - 273.15
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
}
