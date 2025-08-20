#!/usr/bin/env Rscript
# Run: Generate LCZ map + process a user-provided local Landsat stack (manual workflow)
# The automated Google Earth Engine downloader was removed; user supplies data locally.
source("scripts/common.R")
message("== Run: LCZ + Landsat (manual local stack) ==")
roi <- build_roi()
generate_lcz_map(roi)

# --- Locate user-provided Landsat stack -----------------------------------------
# Priority order:
# 1. Environment variable LANDSAT_STACK (full path to a GeoTIFF)
# 2. First .tif in input/LANDSAT (recursively) whose name matches 'landsat' (case-insensitive)
# 3. Any .tif in input/LANDSAT (if only one)
landsat_stack <- Sys.getenv("LANDSAT_STACK", unset = "")
if (nzchar(landsat_stack) && !file.exists(landsat_stack)) {
	stop("LANDSAT_STACK specified but file does not exist: ", landsat_stack)
}
if (!nzchar(landsat_stack)) {
	search_dir <- "input/LANDSAT"
	if (dir.exists(search_dir)) {
		files <- list.files(search_dir, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
		if (length(files)) {
			cand <- grep("landsat", basename(files), ignore.case = TRUE, value = TRUE)
			if (length(cand)) {
				# pick the most recently modified matching candidate
				idx <- which(basename(files) %in% cand)
				fsel <- files[idx][which.max(file.info(files[idx])$mtime)]
				landsat_stack <- fsel
			} else if (length(files) == 1) {
				landsat_stack <- files[1]
			} else {
				# choose newest file if multiple
				landsat_stack <- files[which.max(file.info(files)$mtime)]
			}
		}
	}
}
if (!nzchar(landsat_stack)) {
	stop("No Landsat stack found. Provide path via LANDSAT_STACK env var or place a GeoTIFF under input/LANDSAT/.")
}
message("Using Landsat stack: ", landsat_stack)

# Output directory (renamed from LANDSAT_GEE to LANDSAT)
landsat_dir <- "output/LANDSAT"
dir.create(landsat_dir, recursive = TRUE, showWarnings = FALSE)

# --- Helper: detect & normalize LST band to degrees Celsius ---------------------
normalize_lst <- function(r) {
	nm <- names(r)
	# Priority 1: ST_C already present (maybe scaled 0-1 or 0-0.5 if *100 not applied)
	cands_c <- grep("ST_C", nm, value = TRUE, ignore.case = TRUE)
	if (length(cands_c)) {
		b <- r[[cands_c[1]]]
		rng <- as.numeric(global(b, range, na.rm = TRUE))
		scaling <- "none"
		# If values look like 0.20..0.40 assume scaled by 1/100
		if (!any(is.na(rng)) && rng[2] <= 1 && rng[2] > 0.05) {
			b <- b * 100
			scaling <- "multiplied_by_100 (original looked 0-1)"
		}
		return(list(band = b, source = cands_c[1], method = scaling))
	}
	# Priority 2: ST_K present -> convert to Celsius
	cands_k <- grep("ST_K", nm, value = TRUE, ignore.case = TRUE)
	if (length(cands_k)) {
		b <- r[[cands_k[1]]] - 273.15
		return(list(band = b, source = cands_k[1], method = "converted_from_K"))
	}
	# Priority 3: Raw ST_B10 (DN) -> apply scaling factors from USGS docs then K->C
	raw <- grep("ST_B10", nm, value = TRUE, ignore.case = TRUE)
	if (length(raw)) {
		b_dn <- r[[raw[1]]]
		rng <- as.numeric(global(b_dn, range, na.rm = TRUE))
		# Heuristic: if max > 1000 treat as DN (uint16); otherwise maybe already scaled
		if (!any(is.na(rng)) && rng[2] > 1000) {
			# Scale to Kelvin using factors in landsatGEE.py (0.00341802 * DN + 149.0) then to C
			b <- b_dn * 0.00341802 + 149.0 - 273.15
			return(list(band = b, source = raw[1], method = "DN_scaled_to_C"))
		} else {
			# Already scaled close to Kelvin? If typical range 250-330 then convert
			if (rng[2] > 200 && rng[2] < 400) {
				b <- b_dn - 273.15
				return(list(band = b, source = raw[1], method = "K_to_C (assumed)"))
			}
		}
	}
	return(NULL)
}
message("Loading Landsat raster stack ...")
library(terra)
r <- tryCatch(rast(landsat_stack), error = function(e) stop("Failed to read Landsat stack: ", e$message))

# --- Plot Surface Reflectance (simple RGB) -------------------------------------
sr_bands <- grep("SR_B[2-4]", names(r), value = TRUE)
if (length(sr_bands) == 3) {
	message("Plotting RGB using ", paste(sr_bands, collapse=","))
	plot(r[[sr_bands]], rgb = TRUE, main = "Surface Reflectance (RGB)")
} else {
	plot(r[[1]], main = "Surface Reflectance (Single Band)")
}

# --- LST normalization & plotting ----------------------------------------------
lst_info <- normalize_lst(r)
if (is.null(lst_info)) {
	message("No recognizable LST band (ST_C / ST_K / ST_B10) detected.")
} else {
	lst <- lst_info$band
	names(lst) <- "LST_C"
	stats <- as.numeric(global(lst, quantile, probs = c(0,0.05,0.5,0.95,1), na.rm = TRUE))
	message(sprintf("LST source=%s method=%s range=%.2f..%.2f (°C)", lst_info$source, lst_info$method, stats[1], stats[5]))
	plot(lst, main = "Surface Temperature (°C)")
	# Save normalized LST raster & quick PNG
	out_rst <- file.path(landsat_dir, "landsat_LST_C.tif")
	# Avoid overwriting the original file if user already named it similarly
	if (normalizePath(landsat_stack, winslash = "/", mustWork = FALSE) == normalizePath(out_rst, winslash = "/", mustWork = FALSE)) {
		out_rst <- file.path(landsat_dir, "landsat_LST_C_norm.tif")
	}
	try(writeRaster(lst, out_rst, overwrite = TRUE), silent = TRUE)
	png(file.path(landsat_dir, "landsat_LST_C.png"), width = 1200, height = 1600, res = 150)
	plot(lst, main = "Surface Temperature (°C)")
	dev.off()
	message("Wrote normalized LST raster & PNG to ", landsat_dir)
}

message("Done.")