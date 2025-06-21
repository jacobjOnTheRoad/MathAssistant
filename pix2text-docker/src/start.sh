#!/bin/bash
set -e
echo "DEBUG: Starting container at $(date)"
echo "DEBUG: CUDA environment"
env | grep -E 'CUDA|NVIDIA|LD_LIBRARY_PATH'
echo "DEBUG: NVIDIA-SMI output"
nvidia-smi || echo "ERROR: nvidia-smi failed"
echo "DEBUG: Checking /dev/nvidia* devices"
ls -l /dev/nvidia* || echo "ERROR: No NVIDIA devices found"
echo "DEBUG: Disk usage"
df -h
echo "DEBUG: ONNX Runtime providers"
python3 -c "import onnxruntime as ort; print('Providers:', ort.get_available_providers())" || echo "ERROR: ONNX Runtime check failed"
echo "DEBUG: Starting handler"
python3 handler.py
