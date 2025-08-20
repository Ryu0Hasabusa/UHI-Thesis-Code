#!/usr/bin/env Rscript
# Run: Generate LCZ map + latest Landsat (low-cloud) scene
source("scripts/common.R")
message("== Run: LCZ + Landsat (GEE only) ==")
roi <- build_roi()
generate_lcz_map(roi)
# Run the GEE Landsat workflow via Python
gee_script <- "scripts/landsatGEE.py"
gee_cmd <- sprintf("python %s", gee_script)
message("Running GEE Landsat workflow via: ", gee_cmd)
gee_status <- system(gee_cmd, intern = TRUE)
cat(gee_status, sep = "\n")
message("Plotting GEE Landsat output for surface reflectance and temperature...")
library(terra)
gee_dir <- "output/LANDSAT_GEE"
gee_files <- list.files(gee_dir, pattern = "\\.tif$", full.names = TRUE)
if (length(gee_files)) {
	gee_file <- gee_files[which.max(file.info(gee_files)$mtime)]
	r <- rast(gee_file)
	sr_bands <- grep("SR_B[2-4]", names(r), value = TRUE)
	if (length(sr_bands) == 3) {
		plot(r[[sr_bands]], rgb = TRUE, main = "Surface Reflectance (RGB)")
	} else {
		plot(r[[1]], main = "Surface Reflectance (Single Band)")
	}
	lst_band <- grep("LST|ST_B10|ST_C", names(r), value = TRUE)
	if (length(lst_band)) {
		plot(r[[lst_band[1]]], main = "Surface Temperature (LST)")
	} else {
		message("No LST/ST_B10 band found in output.")
	}
} else {
	message("No GEE output .tif files found in output/LANDSAT_GEE.")
}
message("Done.")