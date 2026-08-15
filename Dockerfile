# Self-contained image: Snakemake drives the pipeline and each rule's
# conda env is created on first run via --use-conda.
FROM condaforge/miniforge3:latest

WORKDIR /pipeline

# Snakemake + graphviz for the driver environment
RUN mamba install -y -c conda-forge -c bioconda \
        "snakemake-minimal>=8.0" graphviz && \
    mamba clean -a -y

# Copy the workflow (data/ is expected to be mounted at runtime)
COPY . /pipeline

# Default: run the full pipeline, building per-rule conda envs.
# Mount your data and results directories when running, e.g.:
#   docker run --rm \
#     -v $(pwd)/data:/pipeline/data \
#     -v $(pwd)/results:/pipeline/results \
#     mtdna-variant-calling
CMD ["snakemake", "-s", "workflow/Snakefile", "--cores", "4", "--use-conda"]
