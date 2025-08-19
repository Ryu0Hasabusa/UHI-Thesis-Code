# Auto-install and run Greater Tunis LCZ map generation
# Usage: source("setup_and_run.R")

message("== Greater Tunis LCZ run script ==")

cran_deps <- c("remotes","terra","sf","osmdata")
missing <- setdiff(cran_deps, rownames(installed.packages()))
if (length(missing)) {
  message("Installing CRAN dependencies: ", paste(missing, collapse=", "))
  install.packages(missing)
}

# Install LCZ4r (prefer local path)
local_path <- Sys.getenv("LCZ4R_LOCAL_PATH", unset = "../LCZ4r")
github_ref <- Sys.getenv("LCZ4R_GITHUB_REF", unset = "main")
github_repo <- Sys.getenv("LCZ4R_GITHUB_REPO", unset = "ByMaxAnjos/LCZ4r")
force_reinstall <- toupper(Sys.getenv("LCZ4R_FORCE_REINSTALL", unset = "FALSE")) %in% c("1","TRUE","T","YES","Y")

need_install <- force_reinstall || !requireNamespace("LCZ4r", quietly = TRUE)
if (need_install) {
  if (nzchar(local_path) && dir.exists(local_path)) {
    message("Installing LCZ4r from local path: ", normalizePath(local_path))
    remotes::install_local(local_path, upgrade = "never", dependencies = TRUE, force = force_reinstall)
  } else {
    message("Installing LCZ4r from GitHub repo=", github_repo, " ref=", github_ref)
    remotes::install_github(paste0(github_repo, "@", github_ref), upgrade = "never", force = force_reinstall, dependencies = TRUE)
  }
} else {
  message("LCZ4r already installed (", as.character(packageVersion("LCZ4r")), ") — set LCZ4R_FORCE_REINSTALL=TRUE to reinstall.")
}

suppressPackageStartupMessages({
  library(LCZ4r)
  library(sf)
  library(terra)
  library(osmdata)
})
try(sf::sf_use_s2(FALSE), silent = TRUE)

# Config via env
use_exact_env <- Sys.getenv("GT_USE_EXACT", unset = "TRUE")
use_exact <- toupper(use_exact_env) %in% c("1","TRUE","T","YES","Y")
manual_bbox_env <- Sys.getenv("GT_MANUAL_BBOX", unset = "")
manual_bbox <- NULL
if (nzchar(manual_bbox_env)) {
  parts <- strsplit(manual_bbox_env, "[,; ]+")[[1]]
  if (length(parts) == 4) manual_bbox <- as.numeric(parts)
  if (any(is.na(manual_bbox))) stop("Invalid GT_MANUAL_BBOX value.")
}

names_list <- c("Tunis Governorate", "Ariana Governorate", "Ben Arous Governorate", "Manouba Governorate")

get_poly <- function(nm) {
  if (use_exact) {
    poly_obj <- try(getbb(nm, format_out = "sf_polygon", limit = 1), silent = TRUE)
    if (!inherits(poly_obj, "try-error") && !is.null(poly_obj)) {
      g <- poly_obj$geometry
      if (is.null(g)) g <- poly_obj$multipolygon
      if (is.null(g)) g <- poly_obj$polygon
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

out_dir <- file.path(getwd(), "LCZ4r_output")
if (!dir.exists(out_dir)) dir.create(out_dir)
out_file <- file.path(out_dir, "lcz_map_greater_tunis.tif")
terra::writeRaster(lcz_byte, out_file, datatype = "INT1U", overwrite = TRUE)

roi_file <- file.path(out_dir, "greater_tunis_roi.gpkg")
try(sf::st_write(roi, roi_file, delete_dsn = TRUE), silent = TRUE)

terra::plot(lcz_byte, col = cols, main = "Greater Tunis LCZ", axes = FALSE)
plot(sf::st_geometry(roi), add = TRUE, border = 'cyan', lwd = 2)

ext <- terra::ext(lcz_byte)
message("Saved raster: ", out_file)
message("Saved ROI: ", roi_file)
message("Extent (xmin xmax ymin ymax): ", paste(signif(c(ext[1],ext[2],ext[3],ext[4]),6), collapse = ", "))
message("Done.")
