#!/bin/bash
set -eux
pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
    torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0
pip install --no-cache-dir xformers==0.0.29.post2
pip check
