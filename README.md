# Post-Annotation Singleton Batch Pipeline (R)

## Overview

This R pipeline performs **batch preprocessing of ANNOVAR hg38_multianno CSV files** for downstream **ACMG singleton variant analysis**.

It processes multiple patients in a single run, applies standardized variant filtering, annotates gene panels and OMIM data, and generates **one Excel workbook per patient** containing multiple filtered interpretation sheets.

---

## Key Features

- Batch processing of ANNOVAR `hg38_multianno.csv` files
- Automated patient file detection
- Variant filtering (functional + population frequency filters)
- Annotation with:
  - OMIM phenotypes
  - CeGaT kidney gene panel
  - RCSI gene panel
  - ACMG incidental genes
  - BA exception list
- gnomAD v4.1 integration (exome + genome)
- SpliceAI + REVEL support (if present)
- Per-patient Excel reports (6 structured sheets)
- Full batch logging with success/failure tracking
- Robust error handling (continues even if one sample fails)

---

## Requirements

### R Version
- R ≥ 4.1.0  
- RStudio ≥ 2025.09.2+418 (recommended)

### Required R Packages
The script auto-installs missing dependencies:

- `tidyverse`
- `writexl`

## Install manually if needed:

### Input Data
#### 1. Multianno Files (Required)
Location: multianno_dir  

Naming format:  

<patient_id>.hg38_multianno.csv  

or  

<any_prefix>_<patient_id>.hg38_multianno.csv  

#### Required Columns

Each CSV must contain:

Chr, Start, End, Ref, Alt

GT (genotype: hom / het / .)

Func.refGene

Gene.refGene

ExonicFunc.refGene

gnomad41_exome_AF

gnomad41_genome_AF

*Optional columns (if available):*

DeNovo, Caller

AAChange.refGene

GeneDetail.refGene

REVEL

SpliceAI scores  

#### 2. Reference Files (Required)

Location: ref_dir

File	Required Column  

OMIM_Summary_File.csv	Approved.Symbol, Phenotypes  

CeGaT_KidneyPanel_Jan2021.csv	Gene  

RCSI_Panel_282.csv	Gene  

ACMG_Incidentals_V3.csv	Gene  

BA_Exception_List_2018.csv	Gene  


All files must be CSV format and gene names are case-insensitive.

## Output
### Per Patient Output

#### Each patient generates:

<patient_id>_analysis.xlsx  


#### *Excel Sheets*  

##### Sheet	Description:   

Raw_Data	Full annotated dataset (no filtering)  

Homo	Homozygous variants  

Comp_Het	Compound heterozygous candidates  

Het_Panel	Rare heterozygous variants in gene panels  

Het_0pt001	Rare heterozygous variants outside panels  

Incidentals	ACMG incidental findings (if consent given)  


```r
install.packages(c("tidyverse", "writexl"))
