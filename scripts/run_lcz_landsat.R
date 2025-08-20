#!/usr/bin/env Rscript
# Run: Generate LCZ map + latest Landsat (low-cloud) scene via Earth Engine helper
source("scripts/common.R")
message("== Run: LCZ + Landsat (GEE only) ==")
roi <- build_roi()
generate_lcz_map(roi)

# --- Execute Python EE workflow -------------------------------------------------
gee_script <- "scripts/landsatGEE.py"
gee_cmd <- sprintf("python %s", gee_script)  # could add args later e.g. --force
message("Running GEE Landsat workflow via: ", gee_cmd)
gee_status <- tryCatch(system(gee_cmd, intern = TRUE), error = function(e) paste("[ERROR]", e$message))
cat(gee_status, sep = "\n")

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

message("Processing GEE Landsat outputs ...")
library(terra)
gee_dir <- "output/LANDSAT_GEE"
gee_files <- list.files(gee_dir, pattern = "\\.tif$", full.names = TRUE)
if (!length(gee_files)) {
	message("No GEE output .tif files found in output/LANDSAT_GEE.")
	quit(save = "no", status = 0)
}
# Prefer an original multi-band stack (name contains 'landsat_stack') over derived products like landsat_LST_C.tif
stack_idx <- grep("landsat_stack", basename(gee_files))
if (length(stack_idx)) {
	candidate_files <- gee_files[stack_idx]
	gee_file <- candidate_files[which.max(file.info(candidate_files)$mtime)]
} else {
	# fallback: choose file with largest number of bands
	band_counts <- vapply(gee_files, function(f) {
		tryCatch(nlyr(rast(f)), error = function(e) -1)
	}, numeric(1))
	gee_file <- gee_files[which.max(band_counts)]
}
message("Using stack candidate: ", basename(gee_file))
r <- rast(gee_file)

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
		out_rst <- file.path(gee_dir, "landsat_LST_C.tif")
		# Avoid attempting to overwrite if the source file already IS the target (happens on reruns)
		if (normalizePath(gee_file, winslash = "/", mustWork = FALSE) == normalizePath(out_rst, winslash = "/", mustWork = FALSE)) {
			out_rst <- file.path(gee_dir, "landsat_LST_C_norm.tif")
		}
		try(writeRaster(lst, out_rst, overwrite = TRUE), silent = TRUE)
	png(file.path(gee_dir, "landsat_LST_C.png"), width = 1200, height = 1600, res = 150)
	plot(lst, main = "Surface Temperature (°C)")
	dev.off()
	message("Wrote normalized LST raster & PNG to ", gee_dir)
}

message("Done.")