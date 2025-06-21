from pix2text import Pix2Text
from PIL import Image
import numpy as np
import os
import sys
import logging
import onnxruntime

# Disable CUDA to ensure CPU-only operation
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["TORCH_CUDA_ARCH_LIST"] = ""
os.environ["PYTHONUNBUFFERED"] = "1"

# Set up logging
logging.basicConfig(level=logging.INFO, stream=sys.stdout, force=True)
logger = logging.getLogger(__name__)

def print_cache_contents(cache_dir, indent=0):
    """Recursively list contents of cache directory."""
    if not os.path.exists(cache_dir):
        logger.info(f"{'  ' * indent}Cache directory {cache_dir} does not exist")
        return
    logger.info(f"{'  ' * indent}Contents of {cache_dir}:")
    for item in os.listdir(cache_dir):
        item_path = os.path.join(cache_dir, item)
        logger.info(f"{'  ' * (indent + 1)}{item}")
        if os.path.isdir(item_path):
            print_cache_contents(item_path, indent + 2)

def main():
    try:
        logger.info("Available ONNX providers: %s", onnxruntime.get_available_providers())
        logger.info("Downloading Pix2Text models on CPU")
        # Initialize with device='cpu' and CPU-only providers
        p2t = Pix2Text.from_config(device='cpu', use_fast=True, providers=['CPUExecutionProvider'])
        # Create a dummy image to trigger model downloads
        dummy_image = Image.fromarray(np.zeros((100, 100, 3), dtype=np.uint8))
        # Perform a dummy recognition to cache models
        result = p2t.recognize(dummy_image)
        logger.info(f"Dummy recognize result: {result}")
        # List model cache directories
        cache_dirs = ['/root/.pix2text', '/root/.cnocr', '/root/.cnstd']
        for cache_dir in cache_dirs:
            print_cache_contents(cache_dir)
        logger.info("Pix2Text models downloaded successfully")
    except Exception as e:
        logger.error(f"Error downloading Pix2Text models: {str(e)}")
        raise

if __name__ == "__main__":
    main()
