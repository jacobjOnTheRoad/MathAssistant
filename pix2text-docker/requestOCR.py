import json
import logging
import os
import time
import base64
import requests
from typing import Dict

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# RunPod configuration
# Note:  Replace the <YOUR API KEY HERE> and the <YOUR RUNPOD ENDPOINT ID HERE> with your API key and your endpoint ID.  Do not include the '<' or '>' characters - those are just being used here as a marker / to make the spot where you put the API key and endpoint more visible.  You don't need to change ANYTHING ELSE about this script, just those two things.
RUNPOD_API_KEY = os.getenv("RUNPOD_API_KEY", "<YOUR API KEY HERE>")
RUNPOD_ENDPOINT = "https://api.runpod.ai/v2/<YOUR RUNPOD ENDPOINT ID HERE>"
TIMEOUT = 60  # Seconds to wait for job completion
POLL_INTERVAL = 2  # Seconds between status checks

def submit_job(input_file: str) -> str:
    """Submit a job to RunPod and return the job ID."""
    headers = {
        "Authorization": f"Bearer {RUNPOD_API_KEY}",
        "Content-Type": "application/json"
    }
    
    try:
        with open(input_file, 'r') as f:
            payload = json.load(f)
        logger.info("Submitting job to RunPod")
        response = requests.post(f"{RUNPOD_ENDPOINT}/run", headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        job_data = response.json()
        job_id = job_data.get("id")
        logger.info(f"Job submitted: {job_id}")
        return job_id
    except requests.RequestException as e:
        logger.error(f"Failed to submit job: {str(e)}")
        raise
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in input file: {str(e)}")
        raise

def poll_job_status(job_id: str) -> Dict:
    """Poll RunPod for job status until completion or timeout."""
    headers = {
        "Authorization": f"Bearer {RUNPOD_API_KEY}"
    }
    
    try:
        start_time = time.time()
        while time.time() - start_time < TIMEOUT:
            response = requests.get(f"{RUNPOD_ENDPOINT}/status/{job_id}", headers=headers, timeout=10)
            response.raise_for_status()
            status_data = response.json()
            status = status_data.get("status")

            if status == "COMPLETED":
                logger.info(f"Job {job_id} completed")
                return status_data.get("output", {})
            elif status in ["FAILED", "CANCELLED"]:
                logger.error(f"Job {job_id} failed: {status_data}")
                raise Exception(f"Job {status}: {status_data}")
            
            logger.debug(f"Job {job_id} status: {status}, waiting...")
            time.sleep(POLL_INTERVAL)
        
        logger.error(f"Job {job_id} timed out after {TIMEOUT} seconds")
        raise Exception("Job timed out")
    
    except requests.RequestException as e:
        logger.error(f"Failed to poll job status: {str(e)}")
        raise

def main(input_file: str, output_file: str):
    """Submit a job to RunPod and save output to file."""
    try:
        job_id = submit_job(input_file)
        output = poll_job_status(job_id)
        with open(output_file, 'w') as f:
            json.dump(output, f, indent=2)
        logger.info(f"Output saved to {output_file}: {output}")
        
        # Decode LaTeX for logging
        latex_b64 = output.get("latex")
        if latex_b64:
            latex = base64.b64decode(latex_b64).decode("utf-8")
            logger.info(f"Recognized LaTeX: {latex}")
    
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise

if __name__ == "__main__":
    input_file = "base64image.txt"  # Replace with your host path
    output_file = "output.json"
    main(input_file, output_file)
