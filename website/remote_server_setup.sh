#!/bin/bash

# Run as root after setting environment variables

# Configuration variables (set via environment or defaults)
SITE_NAME="${SITE_NAME:-yourdomain}"  # e.g., mywebsite
SITE_TLD="${SITE_TLD:-com}"           # e.g., com, org, net
EMAIL="${EMAIL:-your_email@example.com}"  # For Certbot notifications
WEB_DIR="/var/www/${SITE_NAME}"
SERVER_BLOCK="/etc/nginx/sites-available/${SITE_NAME}"
SERVICE_NAME="math-assistant"

# Validate required environment variables
if [ "$SITE_NAME" = "yourdomain" ]; then
    echo "Error: SITE_NAME must be set to a valid domain (not 'yourdomain')."
    echo "Example: export SITE_NAME='mywebsite' SITE_TLD='com' RUNPOD_API_KEY='your_api_key' RUNPOD_ENDPOINT='https://api.runpod.ai/v2/your_endpoint_id'"
    exit 1
fi
if [ -z "$RUNPOD_API_KEY" ] || [ -z "$RUNPOD_ENDPOINT" ]; then
    echo "Error: RUNPOD_API_KEY and RUNPOD_ENDPOINT must be set."
    echo "Example: export SITE_NAME='mywebsite' SITE_TLD='com' RUNPOD_API_KEY='your_api_key' RUNPOD_ENDPOINT='https://api.runpod.ai/v2/your_endpoint_id'"
    exit 1
fi

# Exit on any error
set -e

# Update and upgrade system
apt update && apt upgrade -y

# Install ufw
apt install ufw -y

# Configure ufw
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw default deny incoming
ufw default allow outgoing
ufw enable
ufw reload

# Install Nginx
apt install nginx -y
systemctl start nginx
systemctl enable nginx

# Create web directory
mkdir -p "$WEB_DIR"
mkdir -p "$WEB_DIR/uploads"

# Set directory permissions
chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"

# Create server block
echo "server {
    listen 80;
    listen [::]:80;
    server_name ${SITE_NAME}.${SITE_TLD} www.${SITE_NAME}.${SITE_TLD};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${SITE_NAME}.${SITE_TLD} www.${SITE_NAME}.${SITE_TLD};

    root $WEB_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /upload {
        proxy_pass http://127.0.0.1:5000/upload;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    add_header X-Frame-Options \"SAMEORIGIN\";
    add_header X-Content-Type-Options \"nosniff\";
    add_header X-XSS-Protection \"1; mode=block\";

    location ~ /\. {
        deny all;
    }
}" > "$SERVER_BLOCK"

# Enable server block
ln -sf "$SERVER_BLOCK" /etc/nginx/sites-enabled/

# Remove default server block
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
if ! nginx -t; then
    echo "Nginx configuration test failed. Check /var/log/nginx/error.log"
    exit 1
fi

# Reload Nginx
systemctl reload nginx

# Check Nginx status
if ! systemctl is-active --quiet nginx; then
    echo "Nginx is not running. Check /var/log/nginx/error.log"
    exit 1
fi

# Install Python and dependencies for server.py
apt install python3 python3-pip -y
pip3 install --force-reinstall fastapi[all] uvicorn requests urllib3==1.26.18 chardet==5.2.0

# Install Certbot
apt install certbot python3-certbot-nginx -y

# Run Certbot non-interactively
echo "Ensure ${SITE_NAME}.${SITE_TLD} points to this server's IP before running Certbot."
certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "${SITE_NAME}.${SITE_TLD}" -d "www.${SITE_NAME}.${SITE_TLD}"

# Test Certbot renewal
certbot renew --dry-run

# Create server.py
echo "from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import os
import shutil
import argparse
import base64
import requests
import time
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_methods=['*'], allow_headers=['*'])
UPLOAD_FOLDER = '/var/www/${SITE_NAME}/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# RunPod configuration
RUNPOD_API_KEY = os.getenv('RUNPOD_API_KEY', '')
RUNPOD_ENDPOINT = os.getenv('RUNPOD_ENDPOINT', 'https://api.runpod.ai/v2/<YOUR RUNPOD ENDPOINT ID HERE>')
TIMEOUT = 180  # Increased to 180 seconds
POLL_INTERVAL = 2  # Seconds between status checks

def submit_job(image_b64: str) -> str:
    '''Submit a job to RunPod and return the job ID.'''
    headers = {
        'Authorization': f'Bearer {RUNPOD_API_KEY}',
        'Content-Type': 'application/json'
    }
    payload = {'input': {'image': image_b64}}
    
    try:
        logger.info('Submitting job to RunPod')
        response = requests.post(f'{RUNPOD_ENDPOINT}/run', headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        job_data = response.json()
        job_id = job_data.get('id')
        logger.info(f'Job submitted: {job_id}')
        return job_id
    except requests.RequestException as e:
        logger.error(f'Failed to submit job: {str(e)}')
        raise

def cancel_job(job_id: str):
    '''Cancel a RunPod job.'''
    headers = {
        'Authorization': f'Bearer {RUNPOD_API_KEY}'
    }
    try:
        logger.info(f'Cancelling job {job_id}')
        response = requests.post(f'{RUNPOD_ENDPOINT}/cancel/{job_id}', headers=headers, timeout=10)
        response.raise_for_status()
        logger.info(f'Job {job_id} cancelled')
    except requests.RequestException as e:
        logger.error(f'Failed to cancel job {job_id}: {str(e)}')

def poll_job_status(job_id: str) -> dict:
    '''Poll RunPod for job status until completion or timeout.'''
    headers = {
        'Authorization': f'Bearer {RUNPOD_API_KEY}'
    }
    
    try:
        start_time = time.time()
        while time.time() - start_time < TIMEOUT:
            response = requests.get(f'{RUNPOD_ENDPOINT}/status/{job_id}', headers=headers, timeout=10)
            response.raise_for_status()
            status_data = response.json()
            status = status_data.get('status')
            logger.info(f'Job {job_id} status: {status}, details: {status_data}')

            if status == 'COMPLETED':
                logger.info(f'Job {job_id} completed')
                output = status_data.get('output', {})
                latex_b64 = output.get('latex')
                if latex_b64:
                    latex = base64.b64decode(latex_b64).decode('utf-8')
                    logger.info(f'Recognized LaTeX: {latex}')
                    return {'latex': latex}
                return {'latex': 'No LaTeX returned'}
            elif status in ['FAILED', 'CANCELLED']:
                logger.error(f'Job {job_id} failed: {status_data}')
                raise Exception(f'Job {status}: {status_data}')
            
            logger.debug(f'Job {job_id} status: {status}, waiting...')
            time.sleep(POLL_INTERVAL)
        
        logger.error(f'Job {job_id} timed out after {TIMEOUT} seconds')
        cancel_job(job_id)  # Cancel job to clear queue
        raise Exception('Job timed out')
    
    except requests.RequestException as e:
        logger.error(f'Failed to poll job status: {str(e)}')
        cancel_job(job_id)  # Cancel job on error
        raise

@app.post('/upload')
async def upload_image(image: UploadFile = File(...)):
    try:
        # Save the image temporarily
        file_path = os.path.join(UPLOAD_FOLDER, image.filename)
        with open(file_path, 'wb') as buffer:
            shutil.copyfileobj(image.file, buffer)
        
        # Convert image to base64
        with open(file_path, 'rb') as image_file:
            image_b64 = base64.b64encode(image_file.read()).decode('utf-8')
        
        # Delete the image
        os.remove(file_path)
        
        # Send to RunPod
        job_id = submit_job(image_b64)
        result = poll_job_status(job_id)
        
        return JSONResponse(content=result)
    except Exception as e:
        # Ensure file is deleted on error
        if os.path.exists(file_path):
            os.remove(file_path)
        return JSONResponse(content={'error': str(e)}, status_code=500)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='FastAPI server with configurable port')
    parser.add_argument('port', type=int, default=5000, nargs='?', help='Port to run the server on (default: 5000)')
    args = parser.parse_args()
    
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=args.port)
" > "$WEB_DIR/server.py"

# Set server.py permissions
chown www-data:www-data "$WEB_DIR/server.py"
chmod 644 "$WEB_DIR/server.py"

# Create systemd service for server.py
echo "[Unit]
Description=Math Assistant FastAPI Server
After=network.target

[Service]
User=www-data
WorkingDirectory=$WEB_DIR
Environment=\"RUNPOD_API_KEY=$RUNPOD_API_KEY\"
Environment=\"RUNPOD_ENDPOINT=$RUNPOD_ENDPOINT\"
ExecStart=/usr/bin/python3 $WEB_DIR/server.py
Restart=always

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/$SERVICE_NAME.service

# Set service permissions
chmod 644 /etc/systemd/system/$SERVICE_NAME.service

# Enable and start the service
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Check service status
if ! systemctl is-active --quiet $SERVICE_NAME; then
    echo "FastAPI service failed to start. Check logs: journalctl -u $SERVICE_NAME.service"
    exit 1
fi

# Add crontab rule to clean up old image files (older than 60 minutes)
echo "0 * * * * find $WEB_DIR/uploads/ -type f -mmin +60 -delete" | crontab -

echo "Setup complete! Visit https://${SITE_NAME}.${SITE_TLD}/index.html to verify."
echo "Check logs if issues arise: tail -f /var/log/nginx/error.log"
echo "FastAPI service logs: journalctl -u $SERVICE_NAME.service"
