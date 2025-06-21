# Robust Dockerfile for ComfyUI with Miniconda and CUDA-enabled torch
FROM python:3.10-bullseye

# Install system dependencies (add gnupg and ca-certificates for GPG key issues)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg ca-certificates wget bzip2 curl git ffmpeg libgl1 libglib2.0-0 build-essential && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install full Miniconda (latest official installer)
ENV CONDA_DIR=/opt/conda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p $CONDA_DIR && \
    rm /tmp/miniconda.sh && \
    $CONDA_DIR/bin/conda clean -afy
ENV PATH=$CONDA_DIR/bin:$PATH

# Set working directory
WORKDIR /app/ComfyUI

# Create and verify comfyui conda environment, install core dependencies (remove soundfile, install via pip later)
RUN conda create -y -n comfyui python=3.10 numpy pip pyyaml pillow requests tqdm scikit-image opencv matplotlib scikit-learn scipy pandas psutil alembic sqlalchemy av aiohttp yarl pydantic pydantic-settings kornia -c conda-forge && \
    conda info --envs && \
    conda run -n comfyui python --version

# Install pip dependencies (including CUDA-enabled torch and others not in conda, and soundfile via pip)
RUN conda run -n comfyui pip install --upgrade pip && \
    conda run -n comfyui pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    conda run -n comfyui pip install soundfile comfyui-frontend-package==1.22.2 comfyui-workflow-templates==0.1.29 comfyui-embedded-docs==0.2.2 \
    torchsde einops transformers>=4.28.1 tokenizers>=0.13.3 sentencepiece safetensors>=0.4.2 spandrel && \
    conda run -n comfyui pip install xformers==0.0.29.post2

# Copy application code
COPY . /app/ComfyUI

# Entrypoint uses the entrypoint script which launches ComfyUI
ENTRYPOINT ["/app/ComfyUI/docker-entrypoint.sh"]
