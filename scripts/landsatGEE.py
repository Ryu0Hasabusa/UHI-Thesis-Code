"""Google Earth Engine Landsat 8/9 C2 L2 SR + Surface Temperature workflow (hardcoded config).

Edit the CONFIG dict below to change behavior instead of using environment variables.
"""


import ee
import geopandas as gpd
import json
import math

CONFIG = {
    "LAT": 36.81,                  # Center of Greater Tunis
    "LON": 10.13,
    "BUFFER_M": 15000,             # 15 km radius for full coverage
    "START": "2023-06-01",
    "END": "2023-09-30",
    "MAX_CLOUD": 20,               # scene-level percent
    "DO_MONTHLY": False,           # monthly composites
    "DO_EXPORT": False,            # queue Drive exports
    "DO_TS": False,                # time series CSV export
    "PREFIX": "tunis",            # export folder/prefix
    "SCALE": 30,                   # meters
    "COLLECTIONS": [
        "LANDSAT/LC08/C02/T1_L2",
        "LANDSAT/LC09/C02/T1_L2"
    ],
    "OUT_DIR": "output/LANDSAT_GEE", # Local output directory in repo
    "OUT_EXT": ".tif"                 # Output file extension
    ,"SINGLE_FILE_TARGET_SCALE": 120,   # Preferred scale (m) for single-file output
    "SINGLE_FILE_BANDS": ["SR_B1","SR_B2","SR_B3","SR_B4","SR_B5","SR_B6","SR_B7","ST_K","ST_C","NDVI"] # Bands for single file
}

# --------------- Init ---------------
try:
    ee.Initialize(project='landsat-r')
except Exception:
    ee.Authenticate()
    ee.Initialize(project='landsat-r')

# Read ROI polygon from GeoJSON (exported by R)
roi_geojson_path = "output/greater_tunis_roi.geojson"
def get_roi_geometry():
    gdf = gpd.read_file(roi_geojson_path)
    # Convert to GeoJSON dict
    geojson_dict = json.loads(gdf.to_json())
    # Use the first feature geometry
    geom = geojson_dict['features'][0]['geometry']
    return ee.Geometry(geom)

AOI = get_roi_geometry()

# --------------- Helpers ---------------
def bit(value, b):
    return value.bitwiseAnd(1 << b).gt(0)

def mask_l2(img):
    qa = img.select('QA_PIXEL')
    clear = bit(qa, 6)
    dilated = bit(qa, 1)
    cirrus = bit(qa, 2)
    cloud = bit(qa, 3)
    shadow = bit(qa, 4)
    snow = bit(qa, 5)
    mask = clear.And(dilated.Not()).And(cirrus.Not()).And(cloud.Not()).And(shadow.Not()).And(snow.Not())
    return img.updateMask(mask)

def scale_add_indices(img):
    optical = img.select('SR_B[1-7]').multiply(0.0000275).add(-0.2)
    st_k = img.select('ST_B10').multiply(0.00341802).add(149.0).rename('ST_K')
    st_c = st_k.subtract(273.15).rename('ST_C')
    ndvi = optical.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI')
    return img.addBands([optical, st_k, st_c, ndvi], overwrite=True)

def load_collection():
    col = ee.ImageCollection(CONFIG["COLLECTIONS"][0])
    for c in CONFIG["COLLECTIONS"][1:]:
        col = col.merge(ee.ImageCollection(c))
    col = (col.filterBounds(AOI)
              .filterDate(CONFIG["START"], CONFIG["END"])
              .filter(ee.Filter.lte('CLOUD_COVER', CONFIG["MAX_CLOUD"]))
              .map(mask_l2)
              .map(scale_add_indices))
    return col

def best_image(col):
    return col.sort('CLOUD_COVER').first()

def monthly_medians(col):
    def month_img(m):
        m = ee.Number(m)
        start = ee.Date(CONFIG["START"]).update(month=m, day=1)
        end = start.advance(1, 'month')
        subset = col.filterDate(start, end)
        return subset.median().set({'month': m, 'system:time_start': start.millis()})
    months = ee.List.sequence(ee.Date(CONFIG["START"]).get('month'), ee.Date(CONFIG["END"]).get('month'))
    return ee.ImageCollection(months.map(month_img))

def export_image(img, name, bands=None, region=None):
    if not CONFIG["DO_EXPORT"]:
        return
    if bands:
        img = img.select(bands)
    region = region or AOI
    task = ee.batch.Export.image.toDrive(
        image=img.clip(region),
    description=f"{CONFIG['PREFIX']}_{name}",
    folder=CONFIG['PREFIX'],
    fileNamePrefix=f"{CONFIG['PREFIX']}_{name}",
        region=region,
    scale=CONFIG['SCALE'],
        maxPixels=1e13
    )
    task.start()
    print(f"Export queued: {name}")

def export_time_series(col):
    if not CONFIG["DO_TS"]:
        return
    # Reduce over AOI centroid for NDVI & ST_C
    def add_vals(img):
        stats = img.reduceRegion(reducer=ee.Reducer.mean(), geometry=AOI.centroid(), scale=CONFIG['SCALE'], maxPixels=1e9)
        return ee.Feature(None, {
            'time': img.date().format('YYYY-MM-dd'),
            'NDVI': stats.get('NDVI'),
            'ST_C': stats.get('ST_C')
        })
    feats = col.map(add_vals).filter(ee.Filter.notNull(['NDVI']))
    fc = ee.FeatureCollection(feats)
    if CONFIG["DO_EXPORT"]:
        task = ee.batch.Export.table.toDrive(
            collection=fc,
            description=f"{CONFIG['PREFIX']}_timeseries",
            folder=CONFIG['PREFIX'],
            fileNamePrefix=f"{CONFIG['PREFIX']}_timeseries",
            fileFormat='CSV'
        )
        task.start()
        print("Export queued: time series CSV")
    # Also print a direct URL (client-side getDownloadURL for small)
    try:
        url = fc.getDownloadURL('CSV')
        print("Time series quick download URL:", url)
    except Exception:
        pass

def main():
    print("[DEBUG] Config:", CONFIG)
    print("[DEBUG] Loading collection...")
    col = load_collection()
    size = col.size().getInfo()
    print(f"[DEBUG] Filtered image count: {size}")
    if size == 0:
        print("[DEBUG] No images found.")
        return
    print("[DEBUG] Selecting best image...")
    img = best_image(col)
    try:
        props = img.select([]).set({'CLOUD_COVER': img.get('CLOUD_COVER')}).getInfo()['properties']
        print(f"[DEBUG] Best image CLOUD_COVER: {props.get('CLOUD_COVER')}")
    except Exception as e:
        print(f"[DEBUG] Exception getting best image properties: {e}")

    # AOI diagnostics
    try:
        a_m2 = AOI.area().getInfo()
        a_km2 = a_m2 / 1e6
        print(f"[DEBUG] AOI area: {a_km2:.2f} km^2")
    except Exception as e:
        print(f"[DEBUG] Exception computing AOI area: {e}")

    print("[DEBUG] Calculating NDVI and ST_C means...")
    try:
        ndvi_mean = img.select('NDVI').reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=AOI,
            scale=CONFIG['SCALE'],
            maxPixels=1e13,
            tileScale=2
        ).get('NDVI')
        st_mean = img.select('ST_C').reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=AOI,
            scale=CONFIG['SCALE'],
            maxPixels=1e13,
            tileScale=2
        ).get('ST_C')
        print(f"[DEBUG] Mean NDVI: {ndvi_mean.getInfo()} Mean ST_C: {st_mean.getInfo()}")
    except Exception as e:
        print(f"[DEBUG] Exception calculating NDVI/ST_C means: {e}")

    print("[DEBUG] Export attempts...")
    try:
        export_image(img.select(['SR_B4','SR_B3','SR_B2']), 'best_truecolor')
        export_image(img.select(['NDVI']), 'best_ndvi')
        export_image(img.select(['ST_C']), 'best_st_c')
        export_image(img.select(['SR_B2','SR_B3','SR_B4','SR_B5','SR_B6','SR_B7','NDVI','ST_K','ST_C']), 'best_stack')
    except Exception as e:
        print(f"[DEBUG] Exception during export_image: {e}")

    if CONFIG["DO_MONTHLY"]:
        print("[DEBUG] Monthly composites...")
        monthly = monthly_medians(col)
        count = monthly.size().getInfo()
        print(f"[DEBUG] Monthly composites count: {count}")
        if CONFIG["DO_EXPORT"]:
            def queue_export(m_img):
                m_img = ee.Image(m_img)
                m = ee.Number(m_img.get('month')).format('%02d').getInfo()
                export_image(m_img.select(['NDVI','ST_C']), f"month_{m}")
            for i in range(count):
                try:
                    queue_export(monthly.toList(count).get(i))
                except Exception as e:
                    print(f"[DEBUG] Exception during monthly export: {e}")

    print("[DEBUG] Export time series...")
    try:
        export_time_series(col)
    except Exception as e:
        print(f"[DEBUG] Exception during export_time_series: {e}")

    print("[DEBUG] Attempting single-file download option (target scale) ...")
    try:
        single_file_download(img, AOI)
    except Exception as e:
        print(f"[DEBUG] Exception during single_file_download wrapper: {e}")

import requests
import zipfile
from pathlib import Path

def download_ee_url(download_url, out_dir=None, out_name=None, force=False):
    """Robust download handler.

    Steps:
      1. Skip if a valid GeoTIFF already exists (unless force=True).
      2. Stream to temporary file (.part) to avoid leaving corrupt targets.
      3. Detect ZIP vs GeoTIFF by magic bytes; extract if ZIP.
      4. Resolve name collisions safely (remove older prior file if needed).
    """
    print(f"[DEBUG] download_ee_url called with: {download_url}")
    out_dir = Path(out_dir or CONFIG["OUT_DIR"])
    out_dir.mkdir(parents=True, exist_ok=True)
    out_name = out_name or f"landsat_stack{CONFIG['OUT_EXT']}"
    final_tif = out_dir / out_name

    def _sig(p: Path):
        try:
            with open(p, 'rb') as f:
                return f.read(4)
        except Exception:
            return b''

    def _is_geotiff_signature(sig: bytes):
        return sig.startswith(b'II*') or sig.startswith(b'MM\x00')

    # Skip if existing appears valid
    if final_tif.exists() and not force:
        sig = _sig(final_tif)
        if _is_geotiff_signature(sig):
            print(f"[DEBUG] Existing valid GeoTIFF present, skipping download: {final_tif.name}")
            return
        else:
            print(f"[DEBUG] Existing file not valid GeoTIFF (sig={sig}); will re-download.")

    tmp_file = final_tif.with_suffix(final_tif.suffix + '.part')
    if tmp_file.exists():
        try: tmp_file.unlink()
        except Exception: pass

    try:
        print(f"[DEBUG] Starting download from {download_url} ...")
        r = requests.get(download_url, stream=True, timeout=300)
        r.raise_for_status()
        with open(tmp_file, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                if chunk:
                    f.write(chunk)
        print(f"[DEBUG] Saved raw download to {tmp_file.resolve()} ({tmp_file.stat().st_size} bytes)")
        sig = _sig(tmp_file)
        if sig.startswith(b'PK'):
            # ZIP archive -> move to .zip then extract first .tif
            zip_path = tmp_file.with_suffix('.zip')
            if zip_path.exists():
                try: zip_path.unlink()
                except Exception: pass
            tmp_file.rename(zip_path)
            print(f"[DEBUG] Detected ZIP; extracting {zip_path.name} ...")
            with zipfile.ZipFile(zip_path, 'r') as zf:
                tif_members = [m for m in zf.namelist() if m.lower().endswith('.tif')]
                if not tif_members:
                    print("[DEBUG] No .tif inside ZIP; contents:", zf.namelist())
                    return
                member = tif_members[0]
                zf.extract(member, path=zip_path.parent)
                extracted = zip_path.parent / member
                if final_tif.exists():
                    try: final_tif.unlink()
                    except Exception: pass
                extracted.rename(final_tif)
                print(f"[DEBUG] Extracted GeoTIFF to {final_tif} (size {final_tif.stat().st_size} bytes)")
            # Keep or remove zip (keeping for provenance)
        else:
            # GeoTIFF directly
            if final_tif.exists():
                try: final_tif.unlink()
                except Exception: pass
            tmp_file.rename(final_tif)
            print(f"[DEBUG] Stored GeoTIFF as {final_tif.name}")
    except Exception as e:
        print(f"[DEBUG] Download failed: {e}")
        # Cleanup temp
        if tmp_file.exists():
            try: tmp_file.unlink()
            except Exception: pass

def adaptive_quick_download(img, region, max_bytes=48*1024*1024):
    """Attempt to get a quick download URL by adapting scale and band set so the estimated size < max_bytes."""
    # Candidate band sets (from simpler to richer) to keep size small
    band_sets = [
        ['NDVI','ST_C'],
        ['SR_B4','NDVI','ST_C'],
        ['SR_B4','SR_B5','NDVI','ST_C'],
        ['SR_B4','SR_B5','NDVI','ST_K','ST_C']
    ]
    # Candidate scales (meters)
    base_scale = CONFIG['SCALE']
    scales = [base_scale, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    # Compute AOI area (m2)
    try:
        a_m2 = region.area().getInfo()
    except Exception:
        a_m2 = None
    if a_m2:
        print(f"[DEBUG] adaptive_quick_download AOI area: {a_m2/1e6:.2f} km^2")

    def estimate_bytes(bands, scale):
        if not a_m2:
            return math.inf
        # Approx pixel count ignoring masking
        px = a_m2 / (scale * scale)
        # Assume 4 bytes per pixel (float32) per band
        return px * len(bands) * 4

    # Build candidate combos ordered by increasing estimated size
    candidates = []
    for bands in band_sets:
        for sc in scales:
            est = estimate_bytes(bands, sc)
            if est <= max_bytes * 1.2:  # allow some overhead
                candidates.append((est, bands, sc))
    if not candidates:
        # add widest scale simplest bands
        candidates.append((math.inf, band_sets[0], scales[-1]))
    candidates.sort(key=lambda x: x[0])

    for est, bands, sc in candidates:
        print(f"[DEBUG] Trying single download bands={bands} scale={sc} est={est/1024/1024:.2f} MB")
        try:
            subset = img.select(bands).clip(region)
            params = {
                'scale': sc,
                'region': region,
                'filePerBand': False
            }
            url = subset.getDownloadURL(params)
            print(f"[DEBUG] URL attempt: {url}")
            if url:
                suffix = f"_s{sc}m_{'_'.join(bands)}"
                download_ee_url(url, out_name=f"landsat_stack{suffix}{CONFIG['OUT_EXT']}")
                return
            else:
                print("[DEBUG] URL None; trying next candidate.")
        except Exception as e:
            msg = str(e)
            print(f"[DEBUG] Candidate failed: {msg}")
            if 'must be less than or equal' in msg:
                # size issue: continue to next (coarser) candidate
                continue
            # other error types may not be resolved by changing scale
            continue

    # If we reach here, single download failed for all candidates; fallback to tiles
    print("[DEBUG] All single download candidates failed under size/other errors.")
    # Fallback: split region into 4 tiles (bounding box quadrants) and attempt per-tile downloads
    print("[DEBUG] Falling back to tiled downloads (4 quadrants)...")
    try:
        # Get bounding box coordinates client-side
        bbox_coords = region.bounds().coordinates().get(0).getInfo()
        xs = [c[0] for c in bbox_coords]
        ys = [c[1] for c in bbox_coords]
        minx, maxx = min(xs), max(xs)
        miny, maxy = min(ys), max(ys)
        midx = (minx + maxx) / 2.0
        midy = (miny + maxy) / 2.0
        tiles = [
            ee.Geometry.Rectangle([minx, midy, midx, maxy]),  # NW
            ee.Geometry.Rectangle([midx, midy, maxx, maxy]),  # NE
            ee.Geometry.Rectangle([minx, miny, midx, midy]),  # SW
            ee.Geometry.Rectangle([midx, miny, maxx, midy])   # SE
        ]
        for idx, tile in enumerate(tiles, start=1):
            print(f"[DEBUG] Tile {idx} attempting download...")
            try:
                subset_tile = img.select(bands).clip(tile)
                params_tile = {
                    'scale': sc,
                    'region': tile,
                    'filePerBand': False
                }
                url_tile = subset_tile.getDownloadURL(params_tile)
                print(f"[DEBUG] Tile {idx} URL: {url_tile}")
                if url_tile:
                    suffix = f"_tile{idx}_s{sc}m_{'_'.join(bands)}"
                    download_ee_url(url_tile, out_name=f"landsat_stack{suffix}{CONFIG['OUT_EXT']}")
                else:
                    print(f"[DEBUG] Tile {idx} getDownloadURL returned None.")
            except Exception as te:
                print(f"[DEBUG] Tile {idx} download failed: {te}")
    except Exception as e2:
        print(f"[DEBUG] Tiled fallback failed: {e2}")

def single_file_download(img, region, max_bytes=48*1024*1024):
    """Attempt to download a single multi-band file at highest possible resolution near target scale without exceeding size limit."""
    target_scale = CONFIG.get('SINGLE_FILE_TARGET_SCALE', 120)
    bands = CONFIG.get('SINGLE_FILE_BANDS', ['NDVI','ST_C'])
    # Scale ladder: start at target, then finer, then coarser if needed
    finer = [s for s in [90,75,60,45,30] if s < target_scale]
    coarser = [s for s in [150,180,210,240,270,300] if s > target_scale]
    scales_order = [target_scale] + finer + coarser
    print(f"[DEBUG] single_file_download trying bands={bands} scales={scales_order}")
    for sc in scales_order:
        try:
            subset = img.select(bands).clip(region)
            params = {'scale': sc, 'region': region, 'filePerBand': False}
            url = subset.getDownloadURL(params)
            print(f"[DEBUG] Attempt scale {sc} URL: {url}")
            if url:
                suffix = f"_single_s{sc}m_{'_'.join(bands)}"
                download_ee_url(url, out_name=f"landsat_stack{suffix}{CONFIG['OUT_EXT']}")
                return
            else:
                print(f"[DEBUG] Scale {sc} returned None URL; trying next.")
        except Exception as e:
            msg = str(e)
            print(f"[DEBUG] Scale {sc} failed: {msg}")
            if 'must be less than or equal' in msg:
                # size too big, try coarser (later in list) so continue
                continue
            else:
                # Unknown error, still try next scale
                continue
    print("[DEBUG] single_file_download could not obtain single file within limits; invoking adaptive tiling fallback.")
    adaptive_quick_download(img, region)

if __name__ == '__main__':
    main()