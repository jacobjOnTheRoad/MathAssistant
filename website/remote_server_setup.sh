#!/bin/bash

# Run as root after uploading SSH key

# Configuration variables
DOMAIN="myWebSiteName.com"
EMAIL="your_email@example.com"  # Replace with your email for Certbot notifications
WEB_DIR="/var/www/myWebSiteName"
SERVER_BLOCK="/etc/nginx/sites-available/myWebSiteName"

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

# Set directory permissions
chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"

# Create index.html
echo '<!DOCTYPE html>
<html>
<head>
    <title>[website name]</title>
</head>
<body>
    <h1>Welcome to [website name]</h1>
    <p>This is a test page for my site.</p>
</body>
</html>' > "$WEB_DIR/index.html"

# Set index.html permissions
chown www-data:www-data "$WEB_DIR/index.html"
chmod 644 "$WEB_DIR/index.html"

# Create server block
echo "server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;

    root $WEB_DIR;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /recognize {
        proxy_pass http://localhost:8000;
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
ln -s "$SERVER_BLOCK" /etc/nginx/sites-enabled/

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
pip3 install fastapi uvicorn requests pillow

# Install Certbot
apt install certbot python3-certbot-nginx -y

# Run Certbot non-interactively
echo "Ensure $DOMAIN points to this server's IP before running Certbot."
certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN" -d "www.$DOMAIN"

# Test Certbot renewal
certbot renew --dry-run

echo "Setup complete! Visit https://$DOMAIN to verify."
echo "Check logs if issues arise: tail -f /var/log/nginx/error.log"
echo "To run the FastAPI server, copy server.py to $WEB_DIR and run: python3 $WEB_DIR/server.py"
