#!/bin/bash

# Ensure the script is run with root privileges
if [ "$(id -u)" -ne "0" ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

# Update package list and install necessary packages
echo "Updating package list and installing tor and nginx..."
apt update && apt install -y tor nginx || { echo "Failed to install packages. Exiting."; exit 1; }

# Configure Tor hidden service
echo "Configuring Tor hidden service..."
cat <<EOF > /etc/tor/torrc
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 80 127.0.0.1:80
EOF

# Restart Tor to apply the new configuration
echo "Restarting Tor service..."
systemctl restart tor || { echo "Failed to restart Tor. Exiting."; exit 1; }

# Wait for Tor to generate the hidden service hostname
echo "Waiting for Tor to generate the hidden service address..."
while [ ! -f /var/lib/tor/hidden_service/hostname ]; do
    sleep 1
done

# Retrieve the .onion address
ONION_ADDRESS=$(cat /var/lib/tor/hidden_service/hostname)

# Output the hidden service address
echo "Your Tor hidden service address is: $ONION_ADDRESS"

# Ensure the web directory exists and has appropriate permissions
echo "Setting up web directory..."
mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Configure Nginx to serve a simple webpage and directory listing
echo "Configuring Nginx..."
cat <<EOF > /var/www/html/index.html
<html>
<head>
    <title>Welcome to your Hidden Service!</title>
    <style>
        body {
            background-color: black;
            color: green;
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 20px;
        }
        a {
            color: lightgreen;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .directory-listing {
            text-align: left;
            margin: 20px auto;
            width: 80%;
            max-width: 800px;
        }
    </style>
</head>
<body>
    <h1>Success! Your hidden service is working.</h1>
    <p>Onion address: $ONION_ADDRESS</p>
    <div class="directory-listing">
        <!-- Directory listing will be inserted here by Nginx -->
    </div>
</body>
</html>
EOF

# Configure Nginx server block
echo "Creating Nginx server block configuration..."
cat <<EOF > /etc/nginx/sites-available/hidden_service
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        autoindex_format html;
        add_header Content-Type text/html;
    }
}
EOF

# Handle existing symlink
echo "Handling existing symlink..."
if [ -L /etc/nginx/sites-enabled/hidden_service ]; then
    echo "Removing existing symlink..."
    rm /etc/nginx/sites-enabled/hidden_service
fi

# Enable the Nginx server block configuration
echo "Enabling the Nginx server block configuration..."
ln -s /etc/nginx/sites-available/hidden_service /etc/nginx/sites-enabled/ || { echo "Failed to create symlink. Exiting."; exit 1; }

# Remove default configuration if exists
if [ -L /etc/nginx/sites-enabled/default ]; then
    echo "Removing default configuration..."
    rm /etc/nginx/sites-enabled/default
fi

# Test Nginx configuration
echo "Testing Nginx configuration..."
nginx -t || { echo "Nginx configuration test failed. Exiting."; exit 1; }

# Restart Nginx service
echo "Restarting Nginx service..."
systemctl restart nginx || { echo "Failed to restart Nginx. Exiting."; exit 1; }

# Output final message
echo "Nginx is set up to serve your Tor hidden service."
echo "Visit your hidden service at: $ONION_ADDRESS"

