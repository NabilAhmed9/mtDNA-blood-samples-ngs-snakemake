# mtDNA blood samples (NGS; Snakemake)

A reproducible Snakemake workflow for calling variants from human mitochondrial
DNA sequencing data (single-end reads from blood and cheek-swab samples). The
pipeline runs quality control, trimming, mapping to the mitochondrial reference,
duplicate removal, mapping-quality reporting, and multi-sample variant calling,
producing a single VCF for all samples plus an aggregated QC report.

The layout follows the official
[Snakemake tutorial](https://snakemake.readthedocs.io/en/stable/tutorial/tutorial.html):
a `config/config.yaml`, per-stage conda environments under `envs/`, and the
rules in `workflow/Snakefile`.

---

## Pipeline overview

```
                 ┌─ fastqc_raw ─┐
raw FASTQ ──────►│              ├─► multiqc (aggregated QC report)
     │           └─ trimmomatic ─► fastqc_trimmed ─┘
     │                   │
     │                   ▼
     └───────────► bwa_map (read groups) ─► filter_unmapped ─► mark_duplicates
                                                                     │
                                          ┌──────────────────────────┤
                                          ▼                          ▼
                                       qualimap               freebayes ─► all_samples.vcf
```

| Step | Rule              | Tool           | Purpose                                             |
| ---- | ----------------- | -------------- | --------------------------------------------------- |
| 1    | `fastqc_raw`      | FastQC         | QC of raw reads                                     |
| 2    | `trimmomatic`     | Trimmomatic SE | Sliding-window quality trimming                     |
| 3    | `fastqc_trimmed` + `multiqc` | FastQC, MultiQC | QC of trimmed reads, aggregated into one report |
| 4    | `bwa_map`         | BWA-MEM        | Map to `chrM.fa` with explicit read groups, sort    |
| 5    | `filter_unmapped` | SAMtools       | Drop unmapped reads (`-F 4`)                         |
| 6    | `mark_duplicates` | SAMtools       | Remove PCR duplicates                               |
| 7    | `qualimap`        | QualiMap       | Per-sample mapping-quality report                   |
| 8    | `freebayes`       | FreeBayes      | Multi-sample variant calling into one VCF           |
| 9    | (manual)          | IGV            | Visual inspection (see below)                       |

Two reference-prep rules (`bwa_index`, `samtools_faidx`) run automatically if the
BWA index or `.fai` are missing.

---

## Requirements

- Linux (or WSL2 on Windows)
- [Miniforge / Mamba](https://github.com/conda-forge/miniforge)
- Snakemake 8+ (use `--use-conda` so each rule pulls its own pinned environment)

Install the driver environment:

```bash
mamba env create -f environment.yml
conda activate mtdna-snakemake
```

---

## Input data

The raw data is not tracked in this repository (see `.gitignore`). Download the
four single-end FASTQ files and the mitochondrial reference from the public
Galaxy history:

**https://usegalaxy.org/u/dfrisch/h/databloodcheek2024**

Save them into `data/` with these exact names so the workflow can find them:

```
data/
├── Blood-PCR1.fastq
├── Blood-PCR2.fastq
├── Cheek-PCR1.fastq
├── Cheek-PCR2.fastq
└── chrM.fa
```

In Galaxy, use the disk/download icon on each dataset (or "Export" the history)
to retrieve the files. Sample names and the FASTQ extension are set in
`config/config.yaml`; if the exported reads are gzipped, set
`fastq_ext: fastq.gz` (FastQC and Trimmomatic both read gzipped input directly).
Once the five files are in `data/`, the pipeline is fully reproducible from a
single `snakemake --use-conda` call.

---

## Running the pipeline

```bash
# Dry run: see the full plan without executing anything
snakemake -s workflow/Snakefile -n

# Full run, creating each rule's conda environment on first use
snakemake -s workflow/Snakefile --cores 4 --use-conda

# Build a specific target only
snakemake -s workflow/Snakefile --cores 4 --use-conda results/variants/all_samples.vcf

# Force a complete re-run
snakemake -s workflow/Snakefile --cores 4 --use-conda --forceall
```

Visualise the DAG (needs graphviz):

```bash
snakemake -s workflow/Snakefile --dag | dot -Tpng > dag.png
```

Run from the repository root so that the paths in `config.yaml` (`data/`,
`results/`) resolve correctly.

---

## Expected outputs

```
results/
├── qc/
│   ├── raw/       <sample>_fastqc.html / .zip
│   ├── trimmed/   <sample>.trimmed_fastqc.html / .zip
│   └── multiqc/   multiqc_report.html      <- single aggregated QC report
├── trimmed/       <sample>.trimmed.fastq   (+ logs/)
├── bam/           <sample>.sorted.bam, .mapped.bam, .dedup.bam (+ .bai, logs/)
├── qualimap/      <sample>/qualimapReport.html
└── variants/
    └── all_samples.vcf                     <- one multi-sample VCF (4 columns)
```

The MultiQC report is where you judge whether the trimmed reads are good enough
for mapping (per-base quality, adapter content, length distribution before and
after trimming). `all_samples.vcf` has one genotype column per sample, separated
by FreeBayes using the read-group `SM` tags set during mapping.

---

## Viewing the VCF in IGV (Step 9)

1. Open IGV.
2. `Genomes` → `Load Genome from File` → select `data/chrM.fa`.
   (IGV builds the `.fai` on load if needed.)
3. `File` → `Load from File` → select `results/variants/all_samples.vcf`.
4. Optionally load one or more `results/bam/<sample>.dedup.bam` tracks (each with
   its `.bai`) to inspect read support under each called variant.
5. Type `chrM` (or the exact reference contig name) in the locus box to jump to
   the mitochondrial genome, then navigate to variant positions.
6. Export the view with `File` → `Save Image` for the assignment screenshot.

Make sure the contig name in the VCF matches the reference contig name shown in
IGV. If the reference header is `>chrM` the VCF will use `chrM`; if it is `>MT`
they must agree, otherwise IGV shows no variants.

---

## Two things worth checking for mtDNA amplicon data

These do not block the assignment, but they affect interpretation.

**Duplicate removal on PCR amplicons.** Coordinate-based duplicate removal
(Step 6) assumes that reads sharing a start position are PCR duplicates. For
targeted PCR amplicons, many genuine reads legitimately start at the same primer
position, so this step can discard real coverage. The rule is included because
the assignment asks for it; if downstream coverage looks unexpectedly low, try
skipping it by pointing `qualimap`/`freebayes` at `*.mapped.bam` instead of
`*.dedup.bam`.

**Ploidy and heteroplasmy.** FreeBayes runs with diploid defaults here, which
matches the basic Galaxy-style call. Mitochondria are effectively multi-copy and
can be heteroplasmic, so low-frequency real variants may be missed under a
diploid model. To detect heteroplasmy, set in `config/config.yaml`:

```yaml
freebayes:
  extra: "--pooled-continuous --min-alternate-fraction 0.05 --min-alternate-count 2"
```

This reports alternate-allele fractions rather than fixed genotypes. Choose the
mode that matches your biological question and state it when interpreting the VCF.

---

## Running with Docker (optional)

```bash
docker build -t mtdna-variant-calling .
docker run --rm \
  -v $(pwd)/data:/pipeline/data \
  -v $(pwd)/results:/pipeline/results \
  mtdna-variant-calling
```

Mounting `data/` and `results/` keeps inputs and outputs on the host so results
persist after the container exits.

---

