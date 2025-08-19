# Greater Tunis LCZ standalone runner
# Usage: source("scripts/setup_and_run.R")

message("== Greater Tunis LCZ map generation ==")

required_cran <- c("remotes","terra","sf","osmdata","jsonlite")
missing <- setdiff(required_cran, rownames(installed.packages()))
if (length(missing)) {
  install.packages(missing)
}

local_path <- Sys.getenv("LCZ4R_LOCAL_PATH", unset = "../LCZ4r")
github_repo <- Sys.getenv("LCZ4R_GITHUB_REPO", unset = "ByMaxAnjos/LCZ4r")
github_ref  <- Sys.getenv("LCZ4R_GITHUB_REF", unset = "main")
force_reinstall <- toupper(Sys.getenv("LCZ4R_FORCE_REINSTALL", unset = "FALSE")) %in% c("1","TRUE","T","YES","Y")

need_install <- force_reinstall || !requireNamespace("LCZ4r", quietly = TRUE)
if (need_install) {
  if (nzchar(local_path) && dir.exists(local_path)) {
    message("Installing LCZ4r from local path: ", normalizePath(local_path))
    remotes::install_local(local_path, upgrade = "never", dependencies = TRUE, force = force_reinstall)
  } else {
    message("Installing LCZ4r from GitHub: ", github_repo, "@", github_ref)
    remotes::install_github(paste0(github_repo, "@", github_ref), upgrade = "never", force = force_reinstall, dependencies = TRUE)
  }
} else {
  message("LCZ4r present (", as.character(packageVersion("LCZ4r")), ")")
}

suppressPackageStartupMessages({
  library(LCZ4r)
  library(sf)
  library(terra)
  library(osmdata)
  library(jsonlite)
})
try(sf::sf_use_s2(FALSE), silent = TRUE)

# Config precedence: env > JSON file > defaults
json_cfg <- list()
if (file.exists("scripts/roi_config.json")) {
  json_cfg <- tryCatch(jsonlite::read_json("scripts/roi_config.json"), error = function(e) { list() })
}
get_cfg <- function(key, default=NULL) {
  envv <- Sys.getenv(toupper(key), unset = NA)
  if (!is.na(envv) && nzchar(envv)) return(envv)
  if (!is.null(json_cfg[[key]])) return(json_cfg[[key]])
  default
}

use_exact <- tolower(get_cfg("GT_USE_EXACT", "TRUE")) %in% c("true","t","1","yes","y")
manual_bbox_raw <- get_cfg("GT_MANUAL_BBOX", "")
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
        bb <- sf::st_bbox(sfpoly)
        message("Got exact polygon for ", nm, " (span ~", signif(bb[["xmax"]]-bb[["xmin"]],3), "x", signif(bb[["ymax"]]-bb[["ymin"]],3), " deg)")
        return(sfpoly)
      }
    }
    message("Exact polygon failed for ", nm, "; using bbox.")
  }
  bb <- try(getbb(nm, format_out = "matrix", limit = 1), silent = TRUE)
  if (inherits(bb, "try-error") || is.null(bb)) stop("No boundary for ", nm)
  message("BBox for ", nm, ": lon [", signif(bb[1,1],4), ", ", signif(bb[1,2],4), "] lat [", signif(bb[2,1],4), ", ", signif(bb[2,2],4), "]")
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
  message("Gathering polygons (strategy: exact sf_polygon -> bbox fallback)…")
  polys <- lapply(names_list, function(nm) tryCatch(get_poly(nm), error = function(e) { message("Failed ", nm, ": ", e$message); NULL }))
  polys <- Filter(Negate(is.null), polys)
  if (!length(polys)) stop("Could not build any polygons.")
  geoms <- lapply(polys, sf::st_geometry)
  polys_sf <- sf::st_as_sf(do.call(c, geoms))
  message("Combining ", length(polys_sf), " polygons…")
  roi <- sf::st_union(polys_sf) |> sf::st_as_sf() |> sf::st_make_valid()
}

bb <- sf::st_bbox(roi)
message("ROI bbox: lon [", signif(bb[["xmin"]],4), ", ", signif(bb[["xmax"]],4), "] lat [", signif(bb[["ymin"]],4), ", ", signif(bb[["ymax"]],4), "]")

message("Downloading & clipping LCZ map…")
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
try(sf::st_write(roi, roi_file, delete_dsn = TRUE), silent = TRUE)

ext <- terra::ext(lcz_byte)
message("Saved raster: ", ras_file)
message("Saved ROI: ", roi_file)
message("Extent (xmin xmax ymin ymax): ", paste(signif(c(ext[1],ext[2],ext[3],ext[4]),6), collapse = ", "))

# Optional quick PNG
png_file <- file.path("output", "lcz_map_greater_tunis.png")
png(png_file, width=1000, height=800)
terra::plot(lcz_byte, col = cols, main = "Greater Tunis LCZ", axes = FALSE)
plot(sf::st_geometry(roi), add = TRUE, border = 'cyan', lwd = 2)
dev.off()

message("Saved preview PNG: ", png_file)
message("Done.")
