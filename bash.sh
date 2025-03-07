#!/bin/bash
# Script Instalasi ZeroTier Self-Hosted Controller + WordPress di VPS Ubuntu/Debian
# Pastikan tidak ada kesalahan dalam instalasi ini

set -e  # Menghentikan script jika terjadi error

# Variabel Konfigurasi
NETWORK_ID="YOUR_NETWORK_ID" # Ganti dengan Network ID yang akan dibuat
MYSQL_ROOT_PASSWORD="strongpassword"
WP_DB_NAME="wordpress"
WP_DB_USER="wp_user"
WP_DB_PASSWORD="wp_password"
DOMAIN_NAME="yourdomain.com"

# Update sistem dan install paket dasar
echo "Updating system and installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php php-curl curl unzip -y

# Install ZeroTier
echo "Installing ZeroTier..."
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable zerotier-one
sudo systemctl start zerotier-one

# Konfigurasi ZeroTier sebagai Controller
echo "Configuring ZeroTier Controller..."
sudo systemctl stop zerotier-one
sudo bash -c 'echo "{ \"settings\": { \"controllerEnabled\": true } }" > /var/lib/zerotier-one/local.conf'
sudo systemctl start zerotier-one

# Membuat Network ID Sendiri
echo "Generating Self-Hosted ZeroTier Network..."
sudo zerotier-idtool initmoon identity.public
sudo zerotier-idtool genmoon identity.public > identity.moon
sudo zerotier-cli orbit `cat identity.public` `cat identity.public`
sudo systemctl restart zerotier-one

# Install WordPress
echo "Installing WordPress..."
cd /var/www/html
sudo wget https://wordpress.org/latest.tar.gz
sudo tar -xzvf latest.tar.gz
sudo mv wordpress/* .
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Konfigurasi MySQL untuk WordPress
echo "Configuring MySQL for WordPress..."
sudo mysql -e "CREATE DATABASE $WP_DB_NAME;"
sudo mysql -e "CREATE USER '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Setup SSL dengan Let's Encrypt (Opsional tapi disarankan)
echo "Installing SSL with Let's Encrypt..."
sudo apt install certbot python3-certbot-apache -y
sudo certbot --apache -d $DOMAIN_NAME --non-interactive --agree-tos -m admin@$DOMAIN_NAME

# Restart Apache
echo "Restarting Apache..."
sudo systemctl restart apache2

echo "Installation Complete!"
echo "WordPress is available at: http://$DOMAIN_NAME/"
echo "ZeroTier Controller is now running on your VPS."
