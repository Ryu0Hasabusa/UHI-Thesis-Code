#!/usr/bin/env Rscript
# Solar Radiation Map (approximate relative solar exposure)
# - Requires a DEM raster. The script looks for DEM at a few common paths and
#   falls back to an error if none found.
# - Computes slope and aspect from the DEM, computes solar declination for
#   monthly mid-days at solar noon (assumes sun azimuth ~ south at noon in
#   northern hemisphere), and averages monthly incidence to produce a relative
#   annual solar exposure raster (0-1).

library(terra)

cat('== Solar radiation (relative exposure) map ==\n')
Sys.setenv(GDAL_NUM_THREADS = 'ALL_CPUS')
terraOptions(memfrac = 0.6)

# Candidate DEM paths (adjust/add if your DEM lives elsewhere)
dem_candidates <- c(
	'input/DEM/dem.tif',
	'input/dem.tif',
	'input/SRTM/srtm.tif',
	'data/dem.tif'
)
dem_path <- NULL
for (p in dem_candidates) if (file.exists(p)) { dem_path <- p; break }

if (is.null(dem_path)) {
	cat('No local DEM found; attempting to fetch DEM using elevatr...\n')
	# require elevatr and sf to fetch DEM
	if (!requireNamespace('elevatr', quietly = TRUE) || !requireNamespace('sf', quietly = TRUE)) {
		stop('Package "elevatr" and "sf" are required to fetch DEM programmatically. Install them or place a DEM at one of: ', paste(dem_candidates, collapse = ', '))
	}

	# try to get ROI from scripts/common.R if available
	roi_sf <- NULL
	if (file.exists('scripts/common.R')) {
		try({ source('scripts/common.R', local = TRUE) }, silent = TRUE)
		if (exists('build_roi')) {
			try({ roi <- build_roi(); if (!inherits(roi, 'try-error')) roi_sf <- sf::st_as_sf(roi) }, silent = TRUE)
		}
	}

	# fallback: derive bbox from first preprocessed scene if available
	if (is.null(roi_sf)) {
		scene_dir <- file.path('input','LANDSAT','scenes')
		scene_files <- list.files(scene_dir, pattern = '_preproc\\.tif$', full.names = TRUE)
		if (length(scene_files) > 0) {
			ref <- try(rast(scene_files[[1]]), silent = TRUE)
			if (!inherits(ref, 'try-error')) {
				e <- ext(ref)
				# create simple polygon in ref CRS then reproject to WGS84
				px <- c(e$xmin, e$xmax, e$xmax, e$xmin, e$xmin)
				py <- c(e$ymin, e$ymin, e$ymax, e$ymax, e$ymin)
				spoly <- sf::st_sfc(sf::st_polygon(list(cbind(px, py))), crs = crs(ref))
				roi_sf <- try(sf::st_transform(spoly, 4326), silent = TRUE)
				if (inherits(roi_sf, 'try-error')) roi_sf <- NULL
			}
		}
	}

	if (is.null(roi_sf)) stop('Could not determine ROI to fetch DEM; please provide a DEM file or ensure scripts/common.R or preprocessed scene files are present.')

	cat('Fetching DEM for ROI (in WGS84) using elevatr::get_elev_raster() - this may take a while\n')
	# choose a moderate zoom; user can adjust if higher resolution is desired
	z <- 12
	dem_r <- try(elevatr::get_elev_raster(locations = roi_sf, z = z, clip = 'locations'), silent = TRUE)
	if (inherits(dem_r, 'try-error') || is.null(dem_r)) stop('elevatr failed to fetch DEM')
	# save to standard path
	dem_path <- file.path('input','DEM','dem.tif')
	dir.create(dirname(dem_path), recursive = TRUE, showWarnings = FALSE)
	# convert to terra raster and write
	dem_terra <- try(rast(dem_r), silent = TRUE)
	if (inherits(dem_terra, 'try-error')) stop('Failed converting fetched DEM to terra raster')
	writeRaster(dem_terra, dem_path, overwrite = TRUE)
	cat('Saved fetched DEM to', dem_path, '\n')
}

cat('Using DEM:', dem_path, '\n')
dem <- rast(dem_path)

# compute slope and aspect from the native DEM (slope in radians, aspect in radians)
cat('Computing slope and aspect...\n')
slope <- terrain(dem, v = 'slope', unit = 'radians')
aspect <- terrain(dem, v = 'aspect', unit = 'radians')

# we need latitude per-cell in geographic degrees; reproject a lightweight copy
cat('Projecting DEM to geographic to extract latitude...\n')
dem_ll <- try(project(dem, 'EPSG:4326', method = 'bilinear'), silent = TRUE)
if (inherits(dem_ll, 'try-error')) stop('Failed to reproject DEM to EPSG:4326 for latitude extraction')
lat_deg <- init(dem_ll, 'y')
lat_rad <- lat_deg * pi / 180

# solar parameters: assume solar noon azimuth due south (pi radians)
solar_azimuth <- pi

# sample one representative day per month (mid-month)
days <- seq(15, by = 30, length.out = 12)

monthly_rasters <- list()
cat('Computing monthly incidence (approximation) for', length(days), 'months...\n')
for (i in seq_along(days)) {
	d <- days[i]
	# solar declination approximation (degrees)
	dec_deg <- 23.44 * sin(2 * pi * (284 + d) / 365)
	dec_rad <- dec_deg * pi / 180

	# define function to compute relative irradiance per-pixel
	fun <- function(slp, asp, lat) {
		# slp, asp, lat are in radians; lat is from geographic projection
		# cosine of solar zenith angle at solar noon
		cos_zenith <- sin(lat) * sin(dec_rad) + cos(lat) * cos(dec_rad)
		# clamp numeric noise
		cos_zenith <- pmin(1, pmax(-1, cos_zenith))
		zenith <- acos(cos_zenith)
		# altitude proxy (radians)
		altitude <- pi/2 - zenith
		sin_alt <- pmax(0, sin(altitude))

		# incidence angle cosine between surface normal and sun vector
		cos_inc <- cos(slp) * cos(zenith) + sin(slp) * sin(zenith) * cos(solar_azimuth - asp)
		cos_inc <- pmax(0, cos_inc)

		# weighted by sun altitude to approximate day-length/irradiance contribution
		val <- cos_inc * sin_alt
		# normalize in [0,1] (will renormalize across months later)
		val
	}

	# use terra::lapp over slope, aspect, lat_rad
	m <- try(lapp(c(slope, aspect, lat_rad), fun = fun), silent = TRUE)
	if (inherits(m, 'try-error')) stop('Monthly incidence computation failed for month index ', i)
	monthly_rasters[[i]] <- m
	cat(' - month', i, 'done\n')
}

cat('Averaging monthly rasters to produce annual relative exposure...\n')
ms <- rast(monthly_rasters)
annual_rel <- app(ms, fun = mean, na.rm = TRUE)
names(annual_rel) <- 'solar_rel_annual'

# normalize to 0-1
mn <- global(annual_rel, 'min', na.rm = TRUE)[1,1]
mx <- global(annual_rel, 'max', na.rm = TRUE)[1,1]
if (!is.na(mn) && !is.na(mx) && mx > mn) annual_rel <- (annual_rel - mn) / (mx - mn)

out_dir <- file.path('output', 'solar_radiation')
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
out_tif <- file.path(out_dir, 'solar_radiation_relative_annual.tif')
cat('Writing output to', out_tif, '\n')
writeRaster(annual_rel, out_tif, overwrite = TRUE)

# quick PNG preview
png(file.path(out_dir, 'solar_radiation_relative_annual.png'), width = 900, height = 700)
plot(annual_rel, main = 'Relative Annual Solar Exposure (0-1)')
dev.off()

cat('Done. Outputs in', out_dir, '\n')
