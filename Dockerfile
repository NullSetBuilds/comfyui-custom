# ========== BUILD STAGE ==========
# Use NVIDIA CUDA devel image which includes build tools and full CUDA toolkit
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 AS builder

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TZ=UTC \
    PATH="/usr/local/cuda-12.4/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:${LD_LIBRARY_PATH}" \
    CUDA_HOME="/usr/local/cuda-12.4" \
    PYTHONPATH="/app/ComfyUI"

# 1. Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs python3-pip python3-dev python3-venv python3-tk \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libgl1-mesa-glx libgl1-mesa-dri libglu1-mesa \
    libsndfile1 libavcodec-dev libavformat-dev libavdevice-dev \
    libavfilter-dev libavutil-dev libswscale-dev libswresample-dev \
    libportaudio2 portaudio19-dev wget curl ffmpeg \
    coreutils procps bash grep sed file findutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. Set up ComfyUI and required directories
RUN set -eux && \
    # Remove existing ComfyUI directory if it exists
    rm -rf /app/ComfyUI && \
    # Clone ComfyUI
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI /app/ComfyUI && \
    cd /app/ComfyUI && \
    # Configure git safe directory
    git config --global --add safe.directory /app/ComfyUI && \
    # Checkout custom branch if it exists, otherwise create it
    if ! git show-ref --verify --quiet refs/heads/comfyui-custom; then \
        git checkout -b comfyui-custom; \
    else \
        git checkout comfyui-custom; \
    fi && \
    # Set upstream branch if origin exists
    if git remote | grep -q '^origin$'; then \
        git branch -u origin/comfyui-custom 2>/dev/null || true; \
    fi && \
    # Create a temporary directory for initial files
    mkdir -p /tmp/comfyui_init && \
    # Create the template file with default content
    echo '{"last_node_id": 0, "last_link_id": 0, "nodes": [], "links": [], "groups": [], "config": {}, "extra": {}, "version": 0.4}' > /tmp/comfyui_init/T2I_Template.json && \
    # Create required base directories
    mkdir -p /app/ComfyUI/models/checkpoints && \
    mkdir -p /app/ComfyUI/models/controlnet && \
    mkdir -p /app/ComfyUI/models/diffusers && \
    mkdir -p /app/ComfyUI/models/embeddings && \
    mkdir -p /app/ComfyUI/models/gligen && \
    mkdir -p /app/ComfyUI/models/hypernetworks && \
    mkdir -p /app/ComfyUI/models/loras/recipes && \
    mkdir -p /app/ComfyUI/models/style_models && \
    mkdir -p /app/ComfyUI/models/unet && \
    mkdir -p /app/ComfyUI/models/vae && \
    mkdir -p /app/ComfyUI/models/vae_approx && \
    mkdir -p /app/ComfyUI/models/upscale_models && \
    mkdir -p /app/ComfyUI/models/clip_vision && \
    mkdir -p /app/ComfyUI/models/clip && \
    mkdir -p /app/ComfyUI/models/clip_vision/gligen && \
    mkdir -p /app/ComfyUI/temp && \
    mkdir -p /app/ComfyUI/input && \
    mkdir -p /app/ComfyUI/output && \
    mkdir -p /app/ComfyUI/user && \
    mkdir -p /app/ComfyUI/web/extensions && \
    mkdir -p /app/ComfyUI/my_workflows/T2I_Templates && \
    # Copy the template file
    cp /tmp/comfyui_init/T2I_Template.json /app/ComfyUI/my_workflows/T2I_Templates/ && \
    # Set permissions
    chmod -R 777 /app/ComfyUI/ && \
    # Verify the file was created
    echo "=== Verifying file creation ===" && \
    ls -la /app/ComfyUI/my_workflows/T2I_Templates/ && \
    echo "=== File contents ===" && \
    cat /app/ComfyUI/my_workflows/T2I_Templates/T2I_Template.json && \
    # Verify LoRA recipes directory
    echo "=== Verifying LoRA recipes directory ===" && \
    ls -la /app/ComfyUI/models/loras/recipes/

# 3. Set up Python environment
WORKDIR /app/ComfyUI
# Ensure correct torch stack before anything else
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
        torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
    && pip install --no-cache-dir xformers==0.0.29.post2

# Install pip-tools for dependency management
RUN pip install --no-cache-dir pip-tools
RUN pip install --no-cache-dir pipdeptree

# 3.1 Install PyTorch with CUDA 12.4 and set CUDA architecture restrictions
ENV TORCH_CUDA_ARCH_LIST=8.0;8.6;8.9;9.0 \
    FORCE_CUDA=1

RUN pip install --no-cache-dir --verbose \
    torch==2.6.0 \
    torchvision==0.21.0 \
    torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu124

# Verify PyTorch version immediately after installation
RUN python3 -c "import torch; print(f'DEBUG: PyTorch version after install: {torch.__version__}');"
RUN pip check

# 3.2 Install xformers separately due to specific torch dependencies
RUN pip install --no-cache-dir xformers==0.0.29.post2
RUN python3 -c "import torch; print(f'Torch version after xformers install: {torch.__version__}'); import xformers; print(f'xformers version: {xformers.__version__}')"

# Copy requirements.in and generate requirements.txt
COPY requirements.in /app/ComfyUI/requirements.in
RUN pip-compile requirements.in
RUN cat requirements.txt # Debugging: Print generated requirements.txt to logs

# Install all dependencies from requirements.txt
# Copy constraints.txt for pip constraints enforcement
COPY constraints.txt /app/ComfyUI/constraints.txt

# Install all dependencies from requirements.txt with constraints
RUN pip install --no-cache-dir -r requirements.txt -c constraints.txt
RUN pip check

# Reinstall torch stack to ensure correct versions after all other installs
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
        torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
    && pip install --no-cache-dir xformers==0.0.29.post2
RUN pip check

# Clone ComfyUI-Impact-Pack
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack

# Install its dependencies (removed from builder stage)
# RUN pip install --no-cache-dir -r /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack/requirements.txt
# RUN pip check

# (Optional) Run install script for model/config setup
RUN python3 /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack/install.py

# Install ComfyUI-Manager with error handling and constraints
RUN set -eux && \
    mkdir -p /app/ComfyUI/custom_nodes && \
    cd /app/ComfyUI/custom_nodes && \
    # Remove existing ComfyUI-Manager if it exists
    rm -rf ComfyUI-Manager && \
    # Clone with retry logic
    max_retries=3 && \
    for i in $(seq 1 $max_retries); do \
        if git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git; then \
            break; \
        elif [ $i -eq $max_retries ]; then \
            echo "Failed to clone ComfyUI-Manager after $max_retries attempts" >&2; \
            exit 1; \
        else \
            echo "Retrying ComfyUI-Manager clone (attempt $i/$max_retries)..." >&2; \
            sleep 5; \
        fi; \
    done && \
    cd ComfyUI-Manager && \
    # pip install --no-cache-dir -r requirements.txt (moved to runtime stage)
    # pip check (moved to runtime stage)
    rm -rf .git .github .gitignore README.md

# Set up ComfyUI environment for builder stage
ENV PYTHONPATH=/app/ComfyUI:${PYTHONPATH}
WORKDIR /app/ComfyUI

# ========== RUNTIME STAGE ==========
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TZ=UTC \
    PATH="/usr/local/cuda-12.4/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:${LD_LIBRARY_PATH}" \
    CUDA_HOME="/usr/local/cuda-12.4" \
    PYTHONPATH="/app/ComfyUI"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python-is-python3 \
    libgl1 libglib2.0-0 libsm6 libxext6 libgl1-mesa-glx \
    libsndfile1 libportaudio2 ffmpeg coreutils procps bash curl git \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install all Python dependencies from requirements.txt
# Copy requirements.txt from builder stage
COPY --from=builder /app/ComfyUI/requirements.txt /app/ComfyUI/requirements.txt
RUN pip install --no-cache-dir -r /app/ComfyUI/requirements.txt
RUN pip check

# Install dependencies for ComfyUI-Impact-Pack
COPY --from=builder /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack/requirements.txt /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack/requirements.txt
RUN pip install --no-cache-dir -r /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack/requirements.txt -c /app/ComfyUI/constraints.txt
RUN pip check

# Install dependencies for ComfyUI-Manager
COPY --from=builder /app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt /app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt
RUN pip install --no-cache-dir -r /app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt -c /app/ComfyUI/constraints.txt
RUN pip check

# Install pip-tools for dependency management (runtime stage)
RUN pip install --no-cache-dir pip-tools -c /app/ComfyUI/constraints.txt

# Copy ComfyUI and necessary files from builder
# Removed: COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages
COPY --from=builder /app/ComfyUI /app/ComfyUI

# Copy ensure-torch.sh into the runtime image and set permissions
COPY ensure-torch.sh /usr/local/bin/ensure-torch.sh
RUN chmod +x /usr/local/bin/ensure-torch.sh

# Create required directories
RUN mkdir -p /app/ComfyUI/{\
    models/checkpoints,\
    models/controlnet,\
    models/diffusers,\
    models/embeddings,\
    models/gligen,\
    models/hypernetworks,\
    models/loras,\
    models/style_models,\
    models/unet,\
    models/vae,\
    models/vae_approx,\
    models/upscale_models,\
    models/clip_vision,\
    models/clip,\
    models/clip_vision/gligen,\
    temp,\
    input,\
    output,\
    user,\
    web/extensions,\
    my_workflows/T2I_Templates\
} \
    && chmod -R 777 /app/ComfyUI

# Set working directory
WORKDIR /app

# Verify PyTorch and torchvision versions
RUN python3 -c "\
import torch; \
import torchvision; \
print(f'PyTorch version: {torch.__version__}'); \
print(f'torchvision version: {torchvision.__version__}'); \
assert torch.__version__.startswith('2.6.0'), 'PyTorch version mismatch'; \
assert torchvision.__version__.startswith('0.21.0'), 'torchvision version mismatch'; \
print('PyTorch and torchvision versions are correct')"

# Expose the default port
EXPOSE 8188

# Set the entrypoint
ENTRYPOINT ["/app/ComfyUI/docker-entrypoint.sh"]

# Default command to run when starting the container
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]

# Copy entrypoint script explicitly and apply fixes
COPY docker-entrypoint.sh /app/ComfyUI/docker-entrypoint.sh
RUN sed -i 's/\r$//' /app/ComfyUI/docker-entrypoint.sh # Convert CRLF to LF
RUN chmod +x /app/ComfyUI/docker-entrypoint.sh

# Verify entrypoint script in runtime stage
RUN echo "--- Verifying /app/ComfyUI in runtime stage ---" && \
    ls -la /app/ComfyUI/ && \
    echo "--- Verifying docker-entrypoint.sh in runtime stage (after sed and chmod) ---" && \
    ls -l /app/ComfyUI/docker-entrypoint.sh && \
    cat /app/ComfyUI/docker-entrypoint.sh # Diagnostic for runtime stage
