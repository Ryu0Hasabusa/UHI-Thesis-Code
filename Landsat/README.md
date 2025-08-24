Landsat data (local only)

This folder is intended to hold local Landsat scene files used by the processing
scripts in this repository. Large binary data are not tracked in Git by default.
Store raw or downloaded imagery here (or on an external drive) and keep this
README to document what the folder contains.

Recommended layout

Landsat/
  <pathrow>/
    <scene_id>/
      *SR_B1.TIF
      *SR_B2.TIF
      *SR_B3.TIF
      *SR_B4.TIF
      *SR_B5.TIF
      *SR_B6.TIF
      *SR_B7.TIF
      *ST_B10.TIF
      *ST_EMIS.TIF
      *QA_PIXEL.TIF

Notes
- Filenames should include the band token (e.g. `SR_B4`, `ST_B10`, `ST_EMIS`, `QA_PIXEL`) so
  `scripts/landsat_scene_prep.R` can discover and match bands by scene.
- Do not commit large TIFFs into the Git repository — use external storage or a
  data server. If you must keep a small pointer file, add a `README.md` or use
  `.gitignore` rules.
- The processing scripts expect per-band median outputs in:
  `output/landsat_medians/<BAND>_median.tif` (created by
  `scripts/landsat_scene_prep.R`).
- To (re)generate medians: run `Rscript scripts/landsat_scene_prep.R` from the
  repository root after placing scenes in this folder.

If you want me to add a `.gitignore`, a small placeholder file, or help
re-download and prepare scenes, tell me which option to use.
