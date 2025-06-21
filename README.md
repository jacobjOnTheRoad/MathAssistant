## An AI Math Assistant

This repository provides components for a math tutor, combining GPU-accelerated LaTeX recognition with a web interface.

### 1. Pix2Text Docker for RunPod Serverless

A Docker image for GPU-accelerated LaTeX recognition using Pix2Text, deployed on RunPod serverless.

## Overview
Contains a Docker configuration which processes base64-encoded images to extract LaTeX using Pix2Text. Optimized for RunPod’s serverless GPU environment.

#2. Website:

A website and Python server script to process image snippets and call the RunPod serverless endpoint for recognition.

#### Overview
Includes a bash script to set up a cloud host as a web server with required pip installs for the Python server script. Also includes a script for calling the Grok API to prompt and get responses to questions.

## Prerequisites
- Docker & Dockerhub account
- RunPod account and API key
- NVIDIA GPU (local or RunPod)
- Linux/Ubuntu (not tested on Windows or Mac - changes likely required for this to work on those)

## Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/jacobjOnTheRoad/MathAssistant.git
   cd pix2text-docker
   docker build -t jacobjOnTheRoad/pix2text-runpod-serverless:cuda12.1.1_ver7 .
   docker push jacobjOnTheRoad/pix2text-runpod-serverless:cuda12.1.1_ver7

2. Create a RunPod serverless endpoint using your RunPod account. Specify the image, e.g., jacobjOnTheRoad/pix2text-runpod-serverless:cuda12.1.1_ver7.

    Note: Uses low-tier GPUs (16GB VRAM, ~20-24 cents/hour). Requests take ~6-10 seconds for small images (200-400 pixels).

3. Create an API key on RunPod (Settings > API Keys > Create).

4.  Grant the API key permissions for your serverless endpoint (Restricted, Read/Write).

The image (~9GB) takes time to initialize on RunPod. No charge for initialization, only for request processing. Check logs in the RunPod dashboard (Serverless pane or worker logs) for debugging.


## Usage:

Copy requestOCR.py somewhere to your host machine so you can use it.  Put base64image.txt in the same folder.
Run:  python3 requestOCR.py.
It will send the image contents in base64image.txt to your RunPod serverless to do recognition on it and will print the LaTeX detected to the terminal.


## Acknowledgements:

The official pix2text creator, Breezedeus (I just dockerized it, I am not the original author of that tool):
Pix2Text: https://github.com/breezedeus/pix2text

RunPod: https://www.runpod.io/

Dockerhub:  https://hub.docker.com


## License: MIT License  (for the MIT Licensse text, see the LICENSE file in this directory)
