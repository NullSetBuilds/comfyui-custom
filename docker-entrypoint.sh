#!/bin/bash
set -e

# Enforce constraints for all pip installs
export PIP_CONSTRAINT="/data/ComfyUI/constraints.txt"

# Path where ComfyUI is installed inside the Docker image (from Dockerfile)
IMAGE_COMFYUI_PATH="/app/ComfyUI"
# Path where ComfyUI will be persistent on the host (via Docker volume)
PERSISTENT_COMFYUI_PATH="/data/ComfyUI"

# Check if ComfyUI's main.py exists on the persistent volume
if [ ! -f "${PERSISTENT_COMFYUI_PATH}/main.py" ]; then
    echo "Persistent ComfyUI directory is empty or incomplete. Copying initial files from image..."
    mkdir -p "${PERSISTENT_COMFYUI_PATH}"
    # Use --no-clobber to avoid overwriting existing files if a partial copy happened
    # Use --recursive and --verbose for better feedback
    cp -rv --no-clobber "${IMAGE_COMFYUI_PATH}/." "${PERSISTENT_COMFYUI_PATH}/"
    echo "Initial copy complete."
fi

# Change to the persistent ComfyUI directory to ensure relative paths work
cd "${PERSISTENT_COMFYUI_PATH}"

# Ensure the template file exists on the persistent volume
TEMPLATE_DIR="${PERSISTENT_COMFYUI_PATH}/my_workflows/T2I_Templates"
TEMPLATE_FILE="${TEMPLATE_DIR}/T2I_Template.json"

# Create directories if they don't exist (on the persistent volume)
mkdir -p "${TEMPLATE_DIR}"
chmod 755 "${TEMPLATE_DIR}" # More restrictive than 777, but usually sufficient

# Always ensure the template file has valid content
echo "Ensuring template file has valid content at ${TEMPLATE_FILE}"
cat > "${TEMPLATE_FILE}" << 'EOL'
{
  "last_node_id": 0,
  "last_link_id": 0,
  "nodes": [],
  "links": [],
  "groups": [],
  "config": {},
  "extra": {},
  "version": 0.4
}
EOL

# Set permissions for the template file
chmod 644 "${TEMPLATE_FILE}" # More restrictive than 666, usually sufficient

# Verify the file exists and is accessible
echo "=== Verifying template file ==="
ls -la "${TEMPLATE_DIR}"
echo "=== File content ==="
cat "${TEMPLATE_FILE}"

echo "=== Verifying Python dependencies at runtime ==="
pip check

# Always update dependencies and enforce torch stack before starting ComfyUI
pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
    torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0
pip install --no-cache-dir xformers==0.0.29.post2
pip check

echo "=== Starting ComfyUI ==="
# Execute the original CMD passed to the entrypoint (e.g., "python main.py --listen ...")
exec "$@"