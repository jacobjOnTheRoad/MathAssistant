After cloning the project, first before proceeding, edit the remote_server_setup.sh:
Find the lines at the top and enter your keys and endpoints for these variables:
SITE_NAME="yourdomain"                # e.g., mywebsite
SITE_TLD="com"                       # e.g., com, org, net
EMAIL="your_email@example.com"       # For Certbot notifications
RUNPOD_API_KEY="your_runpod_api_key" # RunPod API key
RUNPOD_ENDPOINT="https://api.runpod.ai/v2/your_endpoint_id" # RunPod endpoint
GROK_API_KEY="your_grok_api_key"     # Grok API key

Upload the setup file to the server:
scp -i ~/.ssh/<key_name> setup_myWebsite.sh root@<server_ip>:/root/
Run the setup file:
ssh -i ~/.ssh/<key_name> root@<server_ip>
chmod +x /root/setup_myWebsite.sh
./setup_myWebsite.sh

You can use that first command to upload other files also from the web_site folder.

Troubleshooting commands in case the script fails:
tail -f /var/log/nginx/error.log
grep Port /etc/ssh/sshd_config
id www-data
ufw status
ps aux | grep nginx
systemctl status nginx
