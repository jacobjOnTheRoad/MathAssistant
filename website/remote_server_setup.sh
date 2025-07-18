#!/bin/bash

# Run as root after setting environment variables below

# Configuration variables (set these before running the script)
SITE_NAME="yourdomain"                # e.g., mywebsite
SITE_TLD="com"                       # e.g., com, org, net
EMAIL="your_email@example.com"       # For Certbot notifications
RUNPOD_API_KEY="your_runpod_api_key" # RunPod API key
RUNPOD_ENDPOINT="https://api.runpod.ai/v2/your_endpoint_id" # RunPod endpoint
GROK_API_KEY="your_grok_api_key"     # Grok API key

# Derived variables
WEB_DIR="/var/www/${SITE_NAME}"
SERVER_BLOCK="/etc/nginx/sites-available/${SITE_NAME}"
SERVICE_NAME="math-assistant"

# Validate required environment variables
if [ "$SITE_NAME" = "yourdomain" ] || [ "$SITE_TLD" = "com" ] || [ "$EMAIL" = "your_email@example.com" ] || \
   [ "$RUNPOD_API_KEY" = "your_runpod_api_key" ] || [ "$RUNPOD_ENDPOINT" = "https://api.runpod.ai/v2/your_endpoint_id" ] || \
   [ "$GROK_API_KEY" = "your_grok_api_key" ]; then
    echo "Error: All configuration variables must be set to valid values in the script."
    echo "Edit the script and set SITE_NAME, SITE_TLD, EMAIL, RUNPOD_API_KEY, RUNPOD_ENDPOINT, and GROK_API_KEY."
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
chmod 750 "$WEB_DIR/uploads"  # Restrict uploads folder, allow www-data write

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

    location /explain {
        proxy_pass http://127.0.0.1:5000/explain;
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
pip3 install --force-reinstall fastapi[all] uvicorn requests urllib3==1.26.18 chardet==5.2.0 openai

# Install Certbot
apt install certbot python3-certbot-nginx -y

# Run Certbot non-interactively
echo "Ensure ${SITE_NAME}.${SITE_TLD} points to this server's IP before running Certbot."
certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "${SITE_NAME}.${SITE_TLD}" -d "www.${SITE_NAME}.${SITE_TLD}"

# Test Certbot renewal
certbot renew --dry-run

# Create server.py
echo "from fastapi import FastAPI, File, UploadFile, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import shutil
import base64
import requests
import time
import logging
import argparse
from openai import OpenAI, OpenAIError

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Log environment variables for debugging
logger.info(f'Environment variable SITE_NAME: {os.getenv(\"SITE_NAME\", \"Not set\")}')
logger.info(f'Environment variable SITE_TLD: {os.getenv(\"SITE_TLD\", \"Not set\")}')
logger.info(f'Environment variable WEB_DIR: {os.getenv(\"WEB_DIR\", \"Not set\")}')
logger.info(f'Environment variable RUNPOD_API_KEY: {os.getenv(\"RUNPOD_API_KEY\", \"Not set\")[:4]}... (redacted)')
logger.info(f'Environment variable RUNPOD_ENDPOINT: {os.getenv(\"RUNPOD_ENDPOINT\", \"Not set\")}')
logger.info(f'Environment variable GROK_API_KEY: {os.getenv(\"GROK_API_KEY\", \"Not set\")[:4]}... (redacted)')

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_methods=['*'], allow_headers=['*'])

# Environment variables
SITE_NAME = os.getenv('SITE_NAME', 'llmprojectwinter')
SITE_TLD = os.getenv('SITE_TLD', 'com')
WEB_DIR = os.getenv('WEB_DIR', '/var/www/llmprojectwinter')
UPLOAD_FOLDER = os.path.join(WEB_DIR, 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# RunPod configuration
RUNPOD_API_KEY = os.getenv('RUNPOD_API_KEY', '')
RUNPOD_ENDPOINT = os.getenv('RUNPOD_ENDPOINT', 'https://api.runpod.ai/v2/<YOUR RUNPOD ENDPOINT ID HERE>')
TIMEOUT = 180  # Increased to 180 seconds
POLL_INTERVAL = 2  # Seconds between status checks

# Grok API configuration
GROK_API_KEY = os.getenv('GROK_API_KEY', '')
GROK_API_BASE = 'https://api.x.ai/v1'

class LatexRequest(BaseModel):
    latex: str

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
async def upload_image(request: Request, image: UploadFile = File(...)):
    logger.info(f'Received upload request from {request.client.host}, filename: {image.filename}, content-type: {image.content_type}')
    try:
        # Check upload folder permissions
        if not os.access(UPLOAD_FOLDER, os.W_OK):
            logger.error(f'No write permission for upload folder: {UPLOAD_FOLDER}')
            raise HTTPException(status_code=500, detail='Server misconfiguration: No write permission for upload folder')

        # Save the image temporarily
        file_path = os.path.join(UPLOAD_FOLDER, image.filename)
        logger.info(f'Saving image to {file_path}')
        with open(file_path, 'wb') as buffer:
            shutil.copyfileobj(image.file, buffer)
        
        # Verify file was written
        if not os.path.exists(file_path):
            logger.error(f'Failed to save image to {file_path}')
            raise HTTPException(status_code=500, detail='Failed to save uploaded image')
        
        # Convert image to base64
        logger.info(f'Converting image {file_path} to base64')
        with open(file_path, 'rb') as image_file:
            image_b64 = base64.b64encode(image_file.read()).decode('utf-8')
        
        # Delete the image
        logger.info(f'Deleting temporary image {file_path}')
        os.remove(file_path)
        
        # Send to RunPod
        logger.info(f'Submitting job to RunPod for image {image.filename}')
        job_id = submit_job(image_b64)
        result = poll_job_status(job_id)
        
        logger.info(f'Upload successful, result: {result}')
        return JSONResponse(content=result)
    except Exception as e:
        # Ensure file is deleted on error
        if 'file_path' in locals() and os.path.exists(file_path):
            logger.info(f'Cleaning up {file_path} after error')
            os.remove(file_path)
        logger.error(f'Upload failed: {str(e)}')
        raise HTTPException(status_code=500, detail=f'Upload failed: {str(e)}')

@app.post('/explain')
async def explain_formula(request: Request, body: LatexRequest):
    logger.info(f'Raw request body: {await request.body()}')
    latex = body.latex
    logger.info(f'Received LaTeX (base64): {latex}')
    try:
        decoded_latex = base64.b64decode(latex).decode('utf-8')
        logger.info(f'Decoded LaTeX: {decoded_latex}')
    except Exception as e:
        logger.error(f'Failed to decode base64 LaTeX: {str(e)}')
        raise HTTPException(status_code=400, detail=f'Invalid base64 LaTeX: {str(e)}')
    
    if not decoded_latex.strip():
        raise HTTPException(status_code=400, detail='LaTeX formula is required')
    
    logger.info(f'Attempting Grok API call with key: {GROK_API_KEY[:4]}... (redacted)')
    try:
        client = OpenAI(api_key=GROK_API_KEY, base_url=GROK_API_BASE)
        prompt = f"""You are a math tutor for high school students learning algebra and early calculus. Explain the LaTeX formula {decoded_latex} in under 2000 characters using simple, clear language. Focus on its meaning and avoid advanced concepts beyond basic calculus. Include a short, relatable example if helpful.

**Formatting Instructions**:
- Use short sentences and simple words.
- Write concise paragraphs with double line breaks between them.
- Place all display math LaTeX formulas on separate lines, enclosed in \[...\].
- Use $...$ for inline math, keeping it brief.
- Do not embed LaTeX within text lines; separate it clearly.
- End with a short, encouraging note for students."""
        logger.info('Sending request to Grok API')
        response = client.chat.completions.create(
            model='grok-3',
            messages=[
                {'role': 'system', 'content': 'You are Grok, a helpful AI assistant created by xAI.'},
                {'role': 'user', 'content': prompt}
            ],
            max_tokens=2000,  # Reduced to ensure concise responses
            temperature=0.7
        )
        logger.info('Received response from Grok API')
        explanation = response.choices[0].message.content
        logger.info(f'Grok API response for LaTeX {decoded_latex}: {explanation}')
        return JSONResponse(content={'explanation': explanation})
    except OpenAIError as e:
        logger.error(f'Grok API error: {str(e)}')
        raise HTTPException(status_code=500, detail=f'Grok API error: {str(e)}')
    except Exception as e:
        logger.error(f'Failed to get explanation from Grok API: {str(e)}')
        raise HTTPException(status_code=500, detail=f'Failed to get explanation: {str(e)}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='FastAPI server with configurable port')
    parser.add_argument('port', type=int, default=5000, nargs='?', help='Port to run the server on (default: 5000)')
    args = parser.parse_args()
    
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=args.port)
" > "$WEB_DIR/server.py"

# Create index.html
echo "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>Math Assistant</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      margin: 0;
      padding: 10px;
      background-color: #f5f5f5;
    }
    h1 {
      text-align: center;
      font-size: 24px;
      color: #333;
      margin: 10px 0;
    }
    .container {
      display: flex;
      flex-wrap: wrap;
      gap: 15px;
      max-width: 1200px;
      margin: 0 auto;
    }
    .draggable {
      width: 100px;
      height: 100px;
      background: #e0e0e0;
      border: 1px solid #333;
      border-radius: 8px;
      text-align: center;
      line-height: 100px;
      cursor: move;
      touch-action: none;
      user-select: none;
    }
    .drop-zone {
      width: 100%;
      min-height: 200px;
      border: 2px dashed #666;
      background: #fff;
      border-radius: 8px;
      text-align: center;
      padding: 15px;
      box-sizing: border-box;
      font-size: 16px;
      color: #333;
    }
    .drop-zone img {
      max-width: 100%;
      height: auto;
      border-radius: 4px;
      margin-top: 10px;
    }
    .feedback {
      text-align: center;
      margin: 10px 0;
      font-size: 14px;
      color: #333;
    }
    .feedback.success {
      color: #28a745;
    }
    .feedback.error {
      color: #dc3545;
    }
    .latex-display {
      margin: 20px auto;
      max-width: 800px;
      padding: 10px;
      background: #fff;
      border: 1px solid #ccc;
      border-radius: 8px;
      text-align: center;
    }
    .latex-code {
      font-family: monospace;
      font-size: 14px;
      margin: 10px 0;
    }
    .explanation {
      font-size: 14px;
      margin: 10px 0;
      text-align: left;
      padding: 15px;
      background: #f9f9f9;
      border: 1px solid #ddd;
      border-radius: 4px;
      min-height: 50px;
      line-height: 1.5;
      overflow-x: auto;
    }
    .explanation .math-display {
      display: block;
      text-align: center;
      margin: 15px 0;
      font-size: 16px;
    }
    .explanation .math-inline {
      display: inline;
      font-size: 14px;
    }
    .explain-button {
      display: none;
      margin: 10px auto;
      padding: 10px 20px;
      background: #007bff;
      color: #fff;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 16px;
    }
    .explain-button:hover {
      background: #0056b3;
    }
    .explain-button:disabled {
      background: #6c757d;
      cursor: not-allowed;
    }
    .note {
      font-size: 12px;
      color: #666;
      margin: 10px 0;
      text-align: center;
    }
    @media (min-width: 768px) {
      h1 {
        font-size: 32px;
      }
      .container {
        flex-direction: row;
        justify-content: center;
      }
      .draggable {
        width: 120px;
        height: 120px;
        line-height: 120px;
      }
      .drop-zone {
        width: 600px;
        min-height: 400px;
        font-size: 18px;
      }
      .latex-display {
        font-size: 16px;
      }
    }
    @media (min-width: 1024px) {
      .drop-zone {
        width: 800px;
        min-height: 500px;
      }
    }
  </style>
</head>
<body>
  <h1>Math Assistant</h1>
  <div class=\"container\">
    <div class=\"draggable\" id=\"draggable\">Drag Me</div>
    <div class=\"drop-zone\" id=\"dropZone\">Drop Here or Use Camera</div>
    <input type=\"file\" accept=\"image/*\" id=\"cameraInput\" style=\"display: none;\">
  </div>
  <div class=\"feedback\" id=\"feedback\"></div>
  <div class=\"latex-display\" id=\"latexDisplay\" style=\"display: none;\">
    <h2>LaTeX Output</h2>
    <div class=\"latex-code\" id=\"latexCode\"></div>
    <div class=\"latex-rendered\" id=\"latexRendered\"></div>
    <button class=\"explain-button\" id=\"explainButton\">Explain Formula with Grok</button>
    <div class=\"explanation\" id=\"explanation\" style=\"display: none;\"></div>
    <div class=\"note\">For step-by-step solving, use the free Grok tier at <a href=\"https://grok.com\">grok.com</a> or <a href=\"https://x.com\">x.com</a>.</div>
  </div>

  <script src=\"https://unpkg.com/mathjax@3/es5/tex-mml-chtml.js\"></script>
  <script src=\"https://unpkg.com/interactjs@1.10.27/dist/interact.min.js\"></script>
  <script>
    // Placeholder drag-and-drop with Interact.js
    interact('.draggable')
      .draggable({
        listeners: {
          move: function(event) {
            const target = event.target;
            const x = (parseFloat(target.getAttribute('data-x')) || 0) + event.dx;
            const y = (parseFloat(target.getAttribute('data-y')) || 0) + event.dy;
            target.style.transform = \`translate(\${x}px, \${y}px)\`;
            target.setAttribute('data-x', x);
            target.setAttribute('data-y', y);
          }
        }
      });

    const dropZone = document.getElementById('dropZone');
    const cameraInput = document.getElementById('cameraInput');
    const feedback = document.getElementById('feedback');
    const latexDisplay = document.getElementById('latexDisplay');
    const latexCode = document.getElementById('latexCode');
    const latexRendered = document.getElementById('latexRendered');
    const explainButton = document.getElementById('explainButton');
    const explanation = document.getElementById('explanation');
    const originalDropZoneText = dropZone.textContent;

    // Handle mobile tap to trigger camera
    let isProcessing = false;
    const isMobile = /Mobi|Android/i.test(navigator.userAgent);
    if (isMobile) {
      dropZone.addEventListener('touchstart', function(event) {
        if (isProcessing) return;
        isProcessing = true;
        event.preventDefault();
        cameraInput.click();
        setTimeout(() => { isProcessing = false; }, 1000);
      });
      dropZone.addEventListener('click', function(event) {
        if (isProcessing) return;
        isProcessing = true;
        event.preventDefault();
        cameraInput.click();
        setTimeout(() => { isProcessing = false; }, 1000);
      });
    }

    // Handle desktop drop zone
    interact('.drop-zone').dropzone({
      accept: '.draggable',
      ondrop: function(event) {
        if (!isMobile) {
          dropZone.innerHTML = '';
          dropZone.appendChild(event.relatedTarget);
          dropZone.textContent = '';
        }
      }
    });

    // Handle file input (camera or file drop)
    dropZone.addEventListener('dragover', (e) => e.preventDefault());
    dropZone.addEventListener('drop', function(e) {
      e.preventDefault();
      if (e.dataTransfer.files.length) {
        handleFiles(e.dataTransfer.files);
      }
    });
    cameraInput.addEventListener('change', function(e) {
      if (e.target.files.length) {
        handleFiles(e.target.files);
      }
    });

    function handleFiles(files) {
      const file = files[0];
      // Clear drop zone and add new image
      dropZone.innerHTML = '';
      const img = document.createElement('img');
      img.src = URL.createObjectURL(file);
      img.style.maxWidth = '100%';
      dropZone.appendChild(img);

      // Show sending feedback
      feedback.textContent = 'Sending image...';
      feedback.className = 'feedback';

      // Send image to FastAPI server
      const formData = new FormData();
      formData.append('image', file);
      fetch('/upload', {
        method: 'POST',
        body: formData
      })
      .then(response => {
        if (!response.ok) throw new Error(\`Server error: \${response.status}\`);
        return response.json();
      })
      .then(data => {
        feedback.textContent = 'Image sent successfully!';
        feedback.className = 'feedback success';
        const latex = data.latex || 'E = mc^2';
        latexCode.textContent = latex;
        latexRendered.innerHTML = \`\\\\(\${latex}\\\\)\`; // MathJax will render this
        latexDisplay.style.display = 'block';
        explainButton.style.display = 'block';
        explanation.style.display = 'none';
        explanation.textContent = '';
        MathJax.typeset();
      })
      .catch(error => {
        feedback.textContent = \`Failed to connect to server: \${error.message}\`;
        feedback.className = 'feedback error';
        console.error('Error sending image:', error);
        // Fallback LaTeX
        const sampleLatex = 'E = mc^2';
        latexCode.textContent = sampleLatex;
        latexRendered.innerHTML = \`\\\\(\${sampleLatex}\\\\)\`; // MathJax will render this
        latexDisplay.style.display = 'block';
        explainButton.style.display = 'block';
        explanation.style.display = 'none';
        explanation.textContent = '';
        MathJax.typeset();
      });
    }

    // Handle Grok API explanation
    explainButton.addEventListener('click', function() {
      console.log('Explain button clicked'); // Debug button click
      const latex = latexCode.textContent;
      console.log('Raw LaTeX:', latex); // Debug raw LaTeX
      if (!latex.trim()) {
        console.error('No LaTeX content to send');
        feedback.textContent = 'No LaTeX formula to explain';
        feedback.className = 'feedback error';
        return;
      }
      let latexBase64;
      try {
        latexBase64 = btoa(encodeURIComponent(latex)); // Encode LaTeX as base64 with Unicode support
        console.log('Sending LaTeX (base64):', latexBase64); // Debug base64
      } catch (error) {
        console.error('Base64 encoding failed:', error);
        feedback.textContent = 'Failed to encode LaTeX formula';
        feedback.className = 'feedback error';
        return;
      }
      feedback.textContent = 'Requesting explanation from Grok...';
      feedback.className = 'feedback';
      explainButton.disabled = true; // Disable button during request
      
      fetch('/explain', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ latex: latexBase64 }) // Send base64-encoded LaTeX
      })
      .then(response => {
        console.log('Response status:', response.status); // Debug response
        if (!response.ok) throw new Error(\`Failed to get explanation: \${response.status}\`);
        return response.json();
      })
      .then(data => {
        feedback.textContent = 'Explanation received!';
        feedback.className = 'feedback success';
        let explanationText = data.explanation || 'No explanation provided';
        // Replace \[...\] with <span class=\"math-display\">...</span>
        explanationText = explanationText.replace(/\\\\\[(.*?)\\\\\]/g, '<span class=\"math-display\">\\\\[$1\\\\]</span>');
        // Replace $...$ with <span class=\"math-inline\">...</span>
        explanationText = explanationText.replace(/\\\$(.*?)\\\$/g, '<span class=\"math-inline\">\\\\($1\\\\)</span>');
        // Fallback for unclosed LaTeX
        explanationText = explanationText.replace(/\\\\\[.*?$/g, '<span class=\"math-display\">[Unclosed LaTeX]</span>');
        explanationText = explanationText.replace(/\\\\\).*?$/g, '<span class=\"math-inline\">[Unclosed LaTeX]</span>');
        explanation.innerHTML = explanationText;
        explanation.style.display = 'block';
        explainButton.disabled = false; // Re-enable button
        MathJax.typeset(); // Render LaTeX
      })
      .catch(error => {
        feedback.textContent = \`Failed to get explanation: \${error.message}\`;
        feedback.className = 'feedback error';
        console.error('Error getting explanation:', error);
        explanation.textContent = \`Failed to retrieve explanation: \${error.message}\`;
        explanation.style.display = 'block';
        explainButton.disabled = false; // Re-enable button
      });
    });
  </script>
</body>
</html>
" > "$WEB_DIR/index.html"

# Set file permissions
chown www-data:www-data "$WEB_DIR/server.py"
chmod 644 "$WEB_DIR/server.py"
chown www-data:www-data "$WEB_DIR/index.html"
chmod 644 "$WEB_DIR/index.html"

# Create systemd service for server.py
echo "[Unit]
Description=Math Assistant FastAPI Server
After=network.target

[Service]
User=www-data
WorkingDirectory=$WEB_DIR
Environment=\"SITE_NAME=$SITE_NAME\"
Environment=\"SITE_TLD=$SITE_TLD\"
Environment=\"WEB_DIR=$WEB_DIR\"
Environment=\"RUNPOD_API_KEY=$RUNPOD_API_KEY\"
Environment=\"RUNPOD_ENDPOINT=$RUNPOD_ENDPOINT\"
Environment=\"GROK_API_KEY=$GROK_API_KEY\"
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
