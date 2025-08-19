# Download latest available MOD11A1 LST Day/Night for ROI
# Requires env EARTHDATA_USER and EARTHDATA_PASS and package MODIStsp

if (!requireNamespace("MODIStsp", quietly = TRUE)) {
  stop("MODIStsp not installed; ensure ENABLE_MODIS env variable was set before running main script.")
}

suppressPackageStartupMessages({
  library(MODIStsp)
  library(sf)
  library(terra)
})

user <- Sys.getenv("EARTHDATA_USER", unset = "")
pass <- Sys.getenv("EARTHDATA_PASS", unset = "")
if (!nzchar(user) || !nzchar(pass)) stop("EARTHDATA_USER/PASS not set.")

roi_path <- "output/greater_tunis_roi.gpkg"
if (!file.exists(roi_path)) stop("ROI file not found (", roi_path, ")")
roi <- sf::st_read(roi_path, quiet = TRUE)
bb <- sf::st_bbox(roi)

# Determine most recent date: we attempt yesterday (UTC) backwards until success (simple heuristic)
max_days_back <- 7
base_date <- as.Date(Sys.time(), tz = "UTC") - 1
sel_date <- NULL
for (i in 0:max_days_back) {
  d <- base_date - i
  sel_date <- format(d, "%Y.%m.%d")
  # We'll attempt download; if fails, loop continues
  # Build a temporary options list
  out_dir <- file.path("output", "MODIS", "MOD11A1")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  message("Trying MOD11A1 date ", sel_date, "…")
  ok <- try(MODIStsp(gui = FALSE,
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
  if (!inherits(ok, "try-error")) {
    message("Success for date ", sel_date)
    break
  } else {
    sel_date <- NULL
  }
}

if (is.null(sel_date)) {
  warning("Failed to download MOD11A1 for recent dates.")
} else {
  # Post-process: list produced GeoTIFFs and create a simple stack preview
  tifs <- list.files(out_dir, pattern = "MOD11A1.*LST_(Day|Night).*\.tif$", full.names = TRUE)
  if (length(tifs)) {
    message("Downloaded files:\n", paste(basename(tifs), collapse = "\n"))
    # Optional: build VRT
    try({
      rlist <- lapply(tifs, terra::rast)
      stk <- terra::rast(rlist)
      terra::writeRaster(stk, file.path(out_dir, paste0("LST_stack_", gsub("\\.", "_", sel_date), ".tif")), overwrite = TRUE)
    }, silent = TRUE)
  }
}
