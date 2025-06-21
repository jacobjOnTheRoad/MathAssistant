# Use RunPod's recommended base image
FROM runpod/pytorch:2.1.1-py3.10-cuda12.1.1-devel-ubuntu22.04

WORKDIR /app

# Environment variables for optimization and CPU-only build
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV TZ=America/New_York
ENV LANG=C.UTF-8
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH
ENV CUDA_HOME=/usr/local/cuda
ENV NVIDIA_VISIBLE_DEVICES=all
ENV PATH=/usr/local/nvidia/bin:$PATH

#ENV CUDA_VISIBLE_DEVICES=""
#ENV TORCH_CUDA_ARCH_LIST=""

# Install system dependencies, including cuDNN
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libmupdf-dev \
    libopencv-dev \
    git \
    wget \
    gnupg \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && rm cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cudnn9-cuda-12 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

#Update ldconfig cache.
#Do a search for installed libcudnn.so.9 (assumed name of the cudnn version 9 library):
#Look for cudnn mentions in the ldconfig cache, give  a good exit code so it continues even if not found:
RUN echo "CUDA_HOME=$CUDA_HOME" && \
	echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/cudnn.conf && ldconfig && \
    find /usr -name libcudnn.so* || true; \
    ldconfig -p | grep cudnn || true && \
	# Remove conflicting cuDNN 8 library
    rm -f /usr/local/lib/python3.10/dist-packages/nvidia/cudnn/lib/libcudnn.so.8

# Copy and install requirements
COPY builder/requirements.txt .
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    python3 -m pip install --no-cache-dir -r requirements.txt && \
    #python3 -m pip install --no-cache-dir onnxruntime==1.15.1   
    python3 -m pip install --no-cache-dir onnxruntime==1.20.1

# Debug ONNX Runtime and rapidocr_onnxruntime
RUN python3 -c "import onnxruntime as ort; print('ONNX Runtime providers:', ort.get_available_providers())" && \
    python3 -c "import torch; print('PyTorch CUDA:', torch.cuda.is_available(), torch.cuda.device_count())" && \
    python3 -c "from rapidocr_onnxruntime.ch_ppocr_det import TextDetector; print('Imported TextDetector successfully')"; \
	pip show torch | grep nvidia-cudnn-cu12 || true; \
	ldd /usr/local/lib/python3.10/dist-packages/torch/lib/libtorch_cuda.so | grep cudnn || true

# Check GPU access
#RUN #/usr/bin/nvidia-smi || true && \
#   python3 -c "import torch; print('Post-GPU-install PyTorch CUDA:', torch.cuda.is_available(), torch.cuda.device_count())"

# Copy and run CPU-based model download script
COPY src/download_models.py .
RUN python3 -u download_models.py

#The below doesn't work in docker build - I guess the nvidia container passthru stuff doesn't work during docker build, so no GPU then.
# Step 10: Test Pix2Text handler with base64image.txt
COPY src/base64image.txt /tmp/base64image.txt
#COPY src/test_handler.py .
#RUN echo "Testing Pix2Text handler with base64image.txt" && \
#    python3 -u test_handler.py
    
RUN echo "Installing onnxruntime-gpu for runtime" && \
	python3 -m pip uninstall -y onnxruntime && \
	python3 -m pip install --no-cache-dir onnxruntime-gpu==1.20.1

# Copy handler and start script
COPY src/handler.py src/start.sh ./
RUN chmod +x /app/start.sh

# Start the worker
CMD ["/app/start.sh"]
