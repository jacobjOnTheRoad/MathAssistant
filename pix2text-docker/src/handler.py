import runpod
import base64
import io
from PIL import Image
from pix2text import Pix2Text
import logging
import onnxruntime
import sys
import traceback

logging.basicConfig(
    level=logging.DEBUG,
    stream=sys.stdout,
    force=True,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def handler(event):
    try:
        job_id = event.get("id", "unknown")
        logger.debug(f"Job {job_id}: Processing job")
        job_input = event["input"]
        if "image" not in job_input:
            logger.error(f"Job {job_id}: Input must contain 'image' key")
            return {"error": "Input must contain 'image' key with base64-encoded image"}
        
        providers = onnxruntime.get_available_providers()
        logger.debug(f"Job {job_id}: Available ONNX providers: {providers}")
        device = 'cuda' if 'CUDAExecutionProvider' in providers else 'cpu'
        logger.debug(f"Job {job_id}: Using device: {device}")
        
        logger.debug(f"Job {job_id}: Initializing Pix2Text on {device}")
        p2t = Pix2Text.from_config(
            device=device,
            use_fast=True,
            providers=['CUDAExecutionProvider', 'CPUExecutionProvider'] if device == 'cuda' else ['CPUExecutionProvider']
        )
        logger.debug(f"Job {job_id}: Pix2Text initialized")
        
        image_b64 = job_input["image"]
        logger.debug(f"Job {job_id}: Decoding base64 image")
        image_data = base64.b64decode(image_b64)
        image = Image.open(io.BytesIO(image_data))
        logger.debug(f"Job {job_id}: Image loaded")
        
        logger.debug(f"Job {job_id}: Running Pix2Text")
        result = p2t.recognize(image)
        
        logger.debug(f"Job {job_id}: Processing result: {type(result)}")
        if isinstance(result, str):
            latex_output = result
        elif isinstance(result, dict):
            latex_output = result.get('latex', '')
        else:
            logger.error(f"Job {job_id}: Unexpected result type: {type(result)}")
            return {"error": f"Unexpected result type: {type(result)}"}
        
        latex_bytes = latex_output.encode('utf-8')
        latex_b64 = base64.b64encode(latex_bytes).decode('utf-8')
        logger.debug(f"Job {job_id}: Returning base64-encoded LaTeX")
        return {"latex": latex_b64}
    except Exception as e:
        logger.error(f"Job {job_id}: Error processing job: {str(e)}\n{traceback.format_exc()}")
        return {"error": str(e)}

runpod.serverless.start({"handler": handler})
