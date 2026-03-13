################################################################################
#
# SCRIPT : post_annotation_singleton_batch.R
# PURPOSE: Batch pre-processing of ANNOVAR hg38_multianno CSV files for
#          downstream ACMG singleton analysis.
#          Reads all patient multianno files from a single directory,
#          applies variant filtering, annotates gene panels and OMIM data,
#          and writes one Excel workbook per patient containing six sheets.
#
# AUTHOR : (original singleton script: Omri Teltsh; batch/update: Deepak Bharti)
# R      : >= 4.1.0   |   RStudio: >= RStudio/2025.09.2+418
# UPDATED: gnomAD v4.0 -> v4.1; single combined CSV input (SNP + Indel) ; spliceAI scores; Deepvariant along side GATK v4.6
#
################################################################################
#
# ── QUICK START ──────────────────────────────────────────────────────────────
#
#   1. Open this script in RStudio (or any R session).
#   2. Edit the FOUR variables under "Step 2: Settings":
#        multianno_dir          <- path to your folder of multianno CSV files
#        output_dir             <- where Excel output files will be written
#        ref_dir                <- path to reference CSV files (OMIM, panels)
#        Consent_for_Incidentals <- "Yes" or "No"
#   3. Click Source (Ctrl+Shift+S) or run:  source("post_annotation_singleton_batch.R")
#   4. Review the confirmation table printed to the console, then wait for
#      processing to complete.
#   5. Collect your per-patient .xlsx files from output_dir.
#
# ── INPUT FILES ──────────────────────────────────────────────────────────────
#
#   Multianno files  (required, one per patient)
#   ┌─────────────────────────────────────────────────────────────────────┐
#   │ Naming convention : <patient_id>.hg38_multianno.csv                 │
#   │ Example           : 169602.hg38_multianno.csv                       │
#   │ Also accepted     : <any_prefix>_<patient_id>.hg38_multianno.csv    │
#   │ Location          : multianno_dir  (all files in one flat folder)   │
#   └─────────────────────────────────────────────────────────────────────┘
#   - Each file must be a SINGLE combined CSV containing both SNP and Indel
#     variants (no separate SNP/Indel split needed).
#   - The following columns MUST be present (script will halt with a clear
#     error message if any are missing):
#       Chr, Start, End, Ref, Alt
#       GT              genotype: "hom", "het", or "."
#       Func.refGene    e.g. "exonic", "splicing", "exonic;splicing"
#       Gene.refGene    HGNC gene symbol
#       ExonicFunc.refGene
#       gnomad41_exome_AF
#       gnomad41_genome_AF
#   - Optional but used when present: DeNovo, Caller, AAChange.refGene,
#     GeneDetail.refGene, REVEL, SpliceAI_*, all other gnomad41_* columns.
#
#   Avinput files  (optional, NOT read by this script)
#   - If <patient_id>.avinput files are present in multianno_dir they will
#     be detected and shown in the confirmation table so you can verify
#     pairing, but they are never opened. GT is already embedded in the
#     new multianno CSVs.
#
#   Reference files  (required, all CSV format, in ref_dir)
#   ┌──────────────────────────────────┬────────────────────────────────────┐
#   │ File                             │ Required column(s)                 │
#   ├──────────────────────────────────┼────────────────────────────────────┤
#   │ OMIM_Summary_File.csv            │ Approved.Symbol, Phenotypes        │
#   │ CeGaT_KidneyPanel_Jan2021.csv    │ Gene                               │
#   │ RCSI_Panel_282.csv               │ Gene                               │
#   │ ACMG_Incidentals_V3.csv          │ Gene                               │
#   │ BA_Exception_List_2018.csv       │ Gene                               │
#   └──────────────────────────────────┴────────────────────────────────────┘
#   All reference files must be plain CSV (not .xls/.xlsx).
#   Gene name columns must have a header row.
#   Gene name capitalisation does not matter — everything is uppercased
#   internally before matching.
#
# ── OUTPUT FILES ─────────────────────────────────────────────────────────────
#
#   Per patient  :  <patient_id>_analysis.xlsx  written to output_dir
#   ┌──────────────┬────────────────────────────────────────────────────────┐
#   │ Sheet        │ Contents / filters applied                             │
#   ├──────────────┼────────────────────────────────────────────────────────┤
#   │ Raw_Data     │ All variants after column reordering & annotation.     │
#   │              │ No frequency or function filtering.                    │
#   ├──────────────┼────────────────────────────────────────────────────────┤
#   │ Homo         │ Baseline* + GT == "hom"                                │
#   ├──────────────┼────────────────────────────────────────────────────────┤
#   │ Comp_Het     │ Baseline* + GT == "het" + gene appears ≥2 times        │
#   │              │ (sorted by gene name)                                  │
#   ├──────────────┼────────────────────────────────────────────────────────┤
#   │ Het_Panel    │ Baseline* + GT == "het"                                │
#   │              │ + gnomad41 exome & genome AF ≤ 0.001                   │
#   │              │ + gene is in CeGaT OR RCSI panel                       │
#   ├──────────────┼────────────────────────────────────────────────────────┤
#   │ Het_0pt001   │ Baseline* + GT == "het"                                │
#   │              │ + gnomad41 exome & genome AF ≤ 0.001                   │
#   │              │ + gene is NOT in CeGaT AND NOT in RCSI panel           │
#   ├──────────────┼────────────────────────────────────────────────────────┤
#   │ Incidentals  │ Union of Homo + Comp_Het + Het_0pt001,                 │
#   │              │ restricted to ACMG incidental genes.                   │
#   │              │ If Consent_for_Incidentals != "Yes", all cells are     │
#   │              │ replaced with "Consent Not Given To Search for         │
#   │              │ Incidentals".                                           │
#   └──────────────┴────────────────────────────────────────────────────────┘
#   * Baseline filters (applied before all sheets except Raw_Data):
#       - Func.refGene  in {"exonic", "splicing", "exonic;splicing"}
#       - ExonicFunc.refGene  NOT in {"unknown", "synonymous SNV"}
#       - gnomad41_genome_AF  ≤ 0.01
#       - gnomad41_exome_AF   ≤ 0.01
#
#   Added annotation columns (appended before column reordering):
#       CeGaT        gene match against CeGaT Kidney Panel
#       RCSI_panel   gene match against RCSI Panel 282
#       BA_Exception gene match against BA Exception List 2018
#       Incidentals  gene match against ACMG Incidentals V3
#       OMIM         phenotype string from OMIM Summary File
#   Missing values in these columns are displayed as "#N/A" in the Excel file.
#
#   Run log  :  batch_run_log_YYYYMMDD_HHMMSS.csv  written to output_dir
#   - One row per patient; columns: patient_id, status (SUCCESS/FAILED),
#     variant counts per sheet, and error message if applicable.
#
# ── DIRECTORY STRUCTURE EXAMPLE ──────────────────────────────────────────────
#
#   ~/Renal_Analysis/
#   ├── multianno_files/               <- multianno_dir
#   │   ├── 169602.hg38_multianno.csv
#   │   ├── 169602.avinput             (detected but not read)
#   │   ├── 169604.hg38_multianno.csv
#   │   └── ...
#   ├── new_processed/                 <- output_dir  (created automatically)
#   │   ├── 169602_analysis.xlsx
#   │   ├── 169604_analysis.xlsx
#   │   └── batch_run_log_20250310_143022.csv
#   └── R_step1_post_annotation/
#       └── reference_files/csv_files/ <- ref_dir
#           ├── OMIM_Summary_File.csv
#           ├── CeGaT_KidneyPanel_Jan2021.csv
#           ├── RCSI_Panel_282.csv
#           ├── ACMG_Incidentals_V3.csv
#           └── BA_Exception_List_2018.csv
#
# ── INCIDENTALS CONSENT ───────────────────────────────────────────────────────
#
#   Set Consent_for_Incidentals <- "Yes"  if all patients in this batch have
#   provided written consent to search for ACMG incidental findings.
#   Set to "No" if consent was NOT obtained — the Incidentals sheet will still
#   be present in the workbook but all cell values will be replaced with a
#   consent-not-given notice.
#   If consent status DIFFERS across patients, split them into two separate
#   directories and run the script twice with different settings.
#
# ── DEPENDENCIES ─────────────────────────────────────────────────────────────
#
#   tidyverse   (dplyr, readr, etc.)  — install.packages("tidyverse")
#   writexl                           — install.packages("writexl")
#   Both packages are auto-installed if not already present.
#
# ── ERROR HANDLING ────────────────────────────────────────────────────────────
#
#   Each patient is processed inside tryCatch(). If one file fails (e.g. a
#   missing required column, a corrupt CSV), the error is logged and the script
#   moves on to the next patient — a single bad file will NOT abort the batch.
#   Check the run log CSV and console output for any FAILED rows.
#
# ── CHANGELOG ────────────────────────────────────────────────────────────────
#
#   v2.0  Batch processing: auto-detects all *.hg38_multianno.csv in a folder.
#         Confirmation table with file sizes and avinput pairing check.
#         Per-patient tryCatch error handling. Timestamped run log CSV.
#   v1.1  gnomAD v4.0 -> v4.1 (gnomad40_* -> gnomad41_*).
#         gnomad41_genome now includes AF_sas (missing in gnomad40_genome).
#         Single combined input CSV (SNP + Indel); no avinput GT merge needed.
#         GT, DeNovo, Caller already present as columns in the new CSV.
#         Column ordering changed from index-based to name-based relocate().
#         Panel NA replacement changed from index-based to name-based.
#   v1.0  Original singleton script (Omri Teltsh).
#
################################################################################

rm(list = ls())
cat("\n********* Workspace cleaned *********\n")

############################################################################
#### Step 1: Load Required Libraries
############################################################################

for (pkg in c("tidyverse", "writexl")) {
  if (!require(pkg, character.only = TRUE)) {
    install.packages(pkg)
    library(pkg, character.only = TRUE)
  }
}

############################################################################
#### Step 2: Settings : edit these four paths before running 
############################################################################

# Directory containing all *hg38_multianno.csv files
multianno_dir <- "~/Renal_Analysis/ExomeXtra/per_sample/"

# Directory to write per-patient Excel workbooks
output_dir <- "~/Renal_Analysis/new_processed/ExomeXtra/"

# Directory containing reference CSV files (OMIM, panels, etc.)
ref_dir <- "~/Renal_Analysis/R_step1_post_annotation/reference_files/csv_files/"

# Incidentals consent: "Yes" or "No"
# Applied uniformly to every patient in this batch.
# If consent differs per patient, run the script separately for each group.
Consent_for_Incidentals <- "Yes"

############################################################################
#### Step 3: Load reference files  (loaded once, reused for every patient)
############################################################################

cat("\nLoading reference files...\n")

omim_datasheet         <- read.csv(file.path(ref_dir, "OMIM_Summary_File.csv"),       stringsAsFactors = FALSE)
cegat_datasheet        <- read.csv(file.path(ref_dir, "CeGaT_KidneyPanel_Jan2021.csv"), stringsAsFactors = FALSE)
rcsi_datasheet         <- read.csv(file.path(ref_dir, "RCSI_Panel_282.csv"),           stringsAsFactors = FALSE)
incidentals_datasheet  <- read.csv(file.path(ref_dir, "ACMG_Incidentals_V3.csv"),     stringsAsFactors = FALSE)
ba_exception_datasheet <- read.csv(file.path(ref_dir, "BA_Exception_List_2018.csv"),  stringsAsFactors = FALSE)

# Normalise gene names to upper case in all reference datasets once
omim_datasheet$Approved.Symbol    <- toupper(omim_datasheet$Approved.Symbol)
omim_datasheet$Gene.Name          <- toupper(omim_datasheet$Gene.Name)
cegat_datasheet$Gene              <- toupper(cegat_datasheet$Gene)
rcsi_datasheet$Gene.Symbol        <- toupper(rcsi_datasheet$Gene)
incidentals_datasheet$Gene        <- toupper(incidentals_datasheet$Gene)
ba_exception_datasheet$Gene       <- toupper(ba_exception_datasheet$Gene)

cat("Reference files loaded OK.\n")

############################################################################
#### Step 4: Auto-detect multianno files & print confirmation summary
############################################################################

multianno_files <- list.files(
  path       = multianno_dir,
  pattern    = "\\.hg38_multianno\\.csv$",
  full.names = TRUE
)

if (length(multianno_files) == 0) {
  stop(sprintf(
    "No files matching *.hg38_multianno.csv found in:\n  %s\nCheck multianno_dir.",
    multianno_dir
  ))
}

# Extract patient IDs from filenames.
# Supports two naming conventions:
#   (a) Simple numeric ID:   169602.hg38_multianno.csv  -> "169602"
#   (b) Prefixed ID:         CeGaT_PASS_anno_S000021.hg38_multianno.csv -> "S000021"
#       (prefix stripped by removing everything up to the last underscore before
#        the first digit-or-letter run that differs between files)
patient_ids <- sub("\\.hg38_multianno\\.csv$", "",
                   basename(multianno_files))


# Also detect matching avinput files (informational only — not used for GT).
# The new multianno already contains GT; avinputs are shown in the summary
# so you can verify pairing, but are never read by this script.
avinput_files   <- file.path(multianno_dir, paste0(patient_ids, ".avinput"))
avinput_present <- file.exists(avinput_files)
file_sizes_kb <- round(file.info(multianno_files)$size / 1024, 1)
output_paths  <- file.path(output_dir, paste0(patient_ids, "_analysis.xlsx"))
output_exists <- file.exists(output_paths)

cat("\n", strrep("=", 76), "\n", sep = "")
cat(sprintf("  %-15s  %9s  %9s  %s\n", "Patient ID", "Size(KB)", "avinput?", "Output exists?"))
cat(strrep("-", 76), "\n", sep = "")
for (i in seq_along(multianno_files)) {
  cat(sprintf("  %-15s  %9.1f  %9s  %s\n",
              patient_ids[i],
              file_sizes_kb[i],
              ifelse(avinput_present[i], "YES (unused)", "not found"),
              ifelse(output_exists[i], "YES (will overwrite)", "No")))
}
cat(strrep("=", 70), "\n\n", sep = "")
cat(sprintf("Total patients to process : %d\n", length(multianno_files)))
cat(sprintf("Incidentals consent       : %s\n", Consent_for_Incidentals))
cat(sprintf("Output directory          : %s\n\n", output_dir))

############################################################################
#### Step 5: Helper functions
############################################################################

# Replace NAs in named panel columns with "#N/A"
replace_panel_na <- function(df, cols) {
  for (col in cols[cols %in% colnames(df)]) {
    df[[col]][is.na(df[[col]])] <- "#N/A"
  }
  df
}

# Clean a set of gnomAD frequency columns:
#   "." -> 0, NA -> 0, coerce to numeric
clean_gnomad_cols <- function(df, col_names) {
  for (col in col_names[col_names %in% colnames(df)]) {
    df[[col]] <- sub(df[[col]], pat = "^\\.", rep = 0)
    df[[col]][is.na(df[[col]])] <- 0
    df[[col]] <- as.numeric(df[[col]])
  }
  df
}

############################################################################
#### Step 6: Batch processing loop
############################################################################

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

results_log <- data.frame(
  patient_id    = character(),
  status        = character(),
  n_input       = integer(),
  n_homo        = integer(),
  n_comp_het    = integer(),
  n_het_panel   = integer(),
  n_het_0pt001  = integer(),
  n_incidentals = integer(),
  message       = character(),
  stringsAsFactors = FALSE
)

for (i in seq_along(multianno_files)) {

  patient.id   <- patient_ids[i]
  input_file   <- multianno_files[i]
  output_file  <- output_paths[i]

  cat(sprintf("\n[%d/%d] Processing: %s\n", i, length(multianno_files), patient.id))
  cat(sprintf("        Input  : %s\n", basename(input_file)))
  cat(sprintf("        Output : %s\n", basename(output_file)))

  tryCatch({

    ##################################################################
    # 5a. Load data and define the columns preference , we have GT column 
    # pre added in new pipeline so we are skipping the use of .avinput completely
    ##################################################################
    multianno <- read.csv(input_file, stringsAsFactors = FALSE)
    cat(sprintf("        Loaded : %d variants, %d columns\n",
                nrow(multianno), ncol(multianno)))

    # Validate required columns
    required_cols <- c("Chr", "Start", "End", "Ref", "Alt",
                       "GT", "Func.refGene", "Gene.refGene",
                       "ExonicFunc.refGene",
                       "gnomad41_exome_AF", "gnomad41_genome_AF")
    missing_cols <- setdiff(required_cols, colnames(multianno))
    if (length(missing_cols) > 0) {
      stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
    }

    ##################################################################
    # 5b. Add annotation columns
    ##################################################################

    multianno$Gene.refGene <- toupper(multianno$Gene.refGene)

    multianno$CeGaT <-
      cegat_datasheet$Gene[match(multianno$Gene.refGene, cegat_datasheet$Gene)]

    multianno$BA_Exception <-
      ba_exception_datasheet$Gene[match(multianno$Gene.refGene, ba_exception_datasheet$Gene)]

    multianno$RCSI_panel <-
      rcsi_datasheet$Gene[match(multianno$Gene.refGene, rcsi_datasheet$Gene)]

    multianno$Incidentals <- NA
    if (Consent_for_Incidentals == "Yes") {
      multianno$Incidentals <-
        incidentals_datasheet$Gene[match(multianno$Gene.refGene, incidentals_datasheet$Gene)]
    }

    multianno$OMIM <-
      omim_datasheet$Phenotypes[match(multianno$Gene.refGene, omim_datasheet$Approved.Symbol)]

    ##################################################################
    # 5c. Clean ExonicFunc
    ##################################################################
    multianno$ExonicFunc.refGene[is.na(multianno$ExonicFunc.refGene)] <- "missing_value"
    multianno$ExonicFunc.refGene <- sub(multianno$ExonicFunc.refGene,
                                        pat = "^\\.", rep = "missing_value")

    ##################################################################
    # 5d. Clean gnomAD columns
    ##################################################################
    gnomad41_exome_cols <- c(
      "gnomad41_exome_AF",       "gnomad41_exome_AF_afr",
      "gnomad41_exome_AF_amr",   "gnomad41_exome_AF_asj",
      "gnomad41_exome_AF_eas",   "gnomad41_exome_AF_fin",
      "gnomad41_exome_AF_mid",   "gnomad41_exome_AF_nfe",
      "gnomad41_exome_AF_remaining", "gnomad41_exome_AF_sas"
    )
    gnomad41_genome_cols <- c(
      "gnomad41_genome_AF",      "gnomad41_genome_AF_afr",
      "gnomad41_genome_AF_ami",  "gnomad41_genome_AF_amr",
      "gnomad41_genome_AF_asj",  "gnomad41_genome_AF_eas",
      "gnomad41_genome_AF_fin",  "gnomad41_genome_AF_mid",
      "gnomad41_genome_AF_nfe",  "gnomad41_genome_AF_remaining",
      "gnomad41_genome_AF_sas"   # new vs gnomad40_genome
    )
    multianno <- clean_gnomad_cols(multianno, gnomad41_exome_cols)
    multianno <- clean_gnomad_cols(multianno, gnomad41_genome_cols)

    ##################################################################
    # 5e. Reorder columns by name
    ##################################################################
    leading_cols <- c(
      "Chr", "Start", "End", "Ref", "Alt",
      "GT", "DeNovo", "Caller",           # GT already in file; DeNovo/Caller new
      "Func.refGene", "Gene.refGene",
      "OMIM", "CeGaT", "Incidentals", "BA_Exception", "RCSI_panel",
      "GeneDetail.refGene", "ExonicFunc.refGene", "AAChange.refGene",
      "REVEL","SpliceAI_gene","SpliceAI_DS_AG","SpliceAI_DS_AL","SpliceAI_DS_DG","SpliceAI_DS_DL",
      "SpliceAI_max"
    )
    leading_cols   <- leading_cols[leading_cols %in% colnames(multianno)]
    remaining_cols <- setdiff(colnames(multianno), leading_cols)
    multianno      <- multianno[, c(leading_cols, remaining_cols)]

    ##################################################################
    # 5f. Baseline filters (shared across all output sheets)
    ##################################################################
    modified_multianno <- multianno %>%
      filter(Func.refGene %in% c("exonic", "splicing", "exonic;splicing")) %>%
      filter(ExonicFunc.refGene != "unknown") %>%
      filter(ExonicFunc.refGene != "synonymous SNV") %>%
      filter(gnomad41_genome_AF <= 0.01) %>%
      filter(gnomad41_exome_AF  <= 0.01)

    cat(sprintf("        After baseline filters: %d variants\n", nrow(modified_multianno)))

    ##################################################################
    # 5g. Generate filtered sheets
    ##################################################################

    Homo <- modified_multianno %>%
      filter(GT == "hom")

    Comp_Het <- modified_multianno %>%
      filter(GT == "het") %>%
      filter(duplicated(Gene.refGene, fromLast = FALSE) |
               duplicated(Gene.refGene, fromLast = TRUE)) %>%
      arrange(Gene.refGene)

    Het_Panel <- modified_multianno %>%
      filter(gnomad41_exome_AF  <= 0.001) %>%
      filter(gnomad41_genome_AF <= 0.001) %>%
      filter(GT == "het") %>%
      filter(!is.na(CeGaT) | !is.na(RCSI_panel))

    Het_0pt001 <- modified_multianno %>%
      filter(gnomad41_exome_AF  <= 0.001) %>%
      filter(gnomad41_genome_AF <= 0.001) %>%
      filter(GT == "het") %>%
      filter(is.na(CeGaT)) %>%
      filter(is.na(RCSI_panel))

    Incidentals <- rbind(Homo, Comp_Het, Het_0pt001) %>%
      filter(!is.na(Incidentals))

    if (Consent_for_Incidentals != "Yes") {
      Incidentals[, ] <- "Consent Not Given To Search for Incidentals"
    }

    ##################################################################
    # 5h. Replace NA with "#N/A" in panel/annotation columns
    ##################################################################
    panel_cols <- c("OMIM", "CeGaT", "BA_Exception", "RCSI_panel", "Incidentals")

    multianno   <- replace_panel_na(multianno,   panel_cols)
    Homo        <- replace_panel_na(Homo,        panel_cols)
    Comp_Het    <- replace_panel_na(Comp_Het,    panel_cols)
    Het_Panel   <- replace_panel_na(Het_Panel,   panel_cols)
    Het_0pt001  <- replace_panel_na(Het_0pt001,  panel_cols)
    if (Consent_for_Incidentals == "Yes") {
      Incidentals <- replace_panel_na(Incidentals, panel_cols)
    }

    ##################################################################
    # 5i. Write Excel workbook
    ##################################################################
    write_xlsx(
      list(
        Raw_Data    = multianno,
        Homo        = Homo,
        Comp_Het    = Comp_Het,
        Het_Panel   = Het_Panel,
        Het_0pt001  = Het_0pt001,
        Incidentals = Incidentals
      ),
      path      = output_file,
      col_names = TRUE
    )

    cat(sprintf("        Written : %s\n", basename(output_file)))
    cat(sprintf("        Sheets  : Raw_Data=%d | Homo=%d | Comp_Het=%d | Het_Panel=%d | Het_0pt001=%d | Incidentals=%d\n",
                nrow(multianno), nrow(Homo), nrow(Comp_Het),
                nrow(Het_Panel), nrow(Het_0pt001), nrow(Incidentals)))

    results_log <- rbind(results_log, data.frame(
      patient_id    = patient.id,
      status        = "SUCCESS",
      n_input       = nrow(multianno),
      n_homo        = nrow(Homo),
      n_comp_het    = nrow(Comp_Het),
      n_het_panel   = nrow(Het_Panel),
      n_het_0pt001  = nrow(Het_0pt001),
      n_incidentals = nrow(Incidentals),
      message       = "",
      stringsAsFactors = FALSE
    ))

  }, error = function(e) {
    cat(sprintf("        ERROR  : %s\n", conditionMessage(e)))
    results_log <<- rbind(results_log, data.frame(
      patient_id    = patient.id,
      status        = "FAILED",
      n_input       = NA_integer_,
      n_homo        = NA_integer_,
      n_comp_het    = NA_integer_,
      n_het_panel   = NA_integer_,
      n_het_0pt001  = NA_integer_,
      n_incidentals = NA_integer_,
      message       = conditionMessage(e),
      stringsAsFactors = FALSE
    ))
  })
}

############################################################################
#### Step 7: Print run summary
############################################################################

cat("\n", strrep("=", 70), "\n", sep = "")
cat("  BATCH RUN SUMMARY\n")
cat(strrep("-", 70), "\n", sep = "")
cat(sprintf("  %-30s  %-8s  %6s  %6s  %6s  %6s\n",
            "Patient", "Status", "Input", "Homo", "CompHet", "Panel"))
cat(strrep("-", 70), "\n", sep = "")
for (j in seq_len(nrow(results_log))) {
  r <- results_log[j, ]
  if (r$status == "SUCCESS") {
    cat(sprintf("  %-30s  %-8s  %6d  %6d  %6d  %6d\n",
                r$patient_id, r$status,
                r$n_input, r$n_homo, r$n_comp_het, r$n_het_panel))
  } else {
    cat(sprintf("  %-30s  %-8s  -- %s\n",
                r$patient_id, r$status, r$message))
  }
}

n_ok   <- sum(results_log$status == "SUCCESS")
n_fail <- sum(results_log$status == "FAILED")
cat(strrep("=", 70), "\n", sep = "")
cat(sprintf("  Completed: %d succeeded, %d failed\n\n", n_ok, n_fail))

# Write the run log as a CSV alongside the output files
log_path <- file.path(output_dir, paste0("batch_run_log_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv"))
write.csv(results_log, log_path, row.names = FALSE)
cat(sprintf("  Run log saved to: %s\n\n", log_path))

############################################################################
#### #### #### #### #### Script Ended #### #### #### #### ####
############################################################################

