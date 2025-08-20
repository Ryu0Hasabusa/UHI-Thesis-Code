#!/usr/bin/env Rscript
# Run: Generate ONLY the LCZ map for Greater Tunis (dependencies must already be installed via setup.R)
source("scripts/common.R")

message("== Run: LCZ map only ==")
roi <- build_roi()
generate_lcz_map(roi)
message("Done.")
