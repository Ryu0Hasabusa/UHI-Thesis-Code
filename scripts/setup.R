#!/usr/bin/env Rscript
# One-time setup: install required packages & (optionally) install LCZ4r.
# Usage (PowerShell):
#   Rscript scripts/setup.R
# Optional env vars (override installs):
#   LCZ4R_LOCAL_PATH  (path to local LCZ4r package directory)
#   LCZ4R_GITHUB_REPO (e.g. ByMaxAnjos/LCZ4r)
#   LCZ4R_GITHUB_REF  (branch/tag)
#   LCZ4R_FORCE_REINSTALL=TRUE to force reinstall

message("== One-time setup ==")

# Ensure a non-interactive CRAN mirror is set (prevents install.packages prompting)
options(repos = c(CRAN = Sys.getenv('CRAN_REPO', unset = 'https://cran.rstudio.com')))

required <- c("remotes","terra","sf","osmdata","jsonlite","rstac","elevatr")
missing <- setdiff(required, rownames(installed.packages()))
if (length(missing)) {
  message("Installing CRAN packages: ", paste(missing, collapse=", "))
  install.packages(missing, repos = getOption('repos'))
} else {
  message("All CRAN deps already present.")
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
  message("LCZ4r already present (", as.character(packageVersion("LCZ4r")), ")")
}

message("Setup complete.")
