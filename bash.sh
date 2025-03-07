#!/bin/bash
# Script Instalasi ZeroTier Self-Hosted Controller + WordPress di VPS Ubuntu/Debian
# Pastikan tidak ada kesalahan dalam instalasi ini

set -e  # Menghentikan script jika terjadi error

# Variabel Konfigurasi
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 12)
WP_DB_NAME="wordpress"
WP_DB_USER="wp_user"
WP_DB_PASSWORD=$(openssl rand -base64 12) # Generate password acak untuk database
DOMAIN_NAME="aksyanet.my.id"
WP_ADMIN_USER=""
WP_ADMIN_PASSWORD=""

# Update sistem dan install paket dasar
echo "Updating system and installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php php-curl curl unzip certbot python3-certbot-apache git -y

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
NETWORK_ID=$(sudo zerotier-cli listnetworks | awk 'NR==2{print $3}')

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

# Setup SSL dengan Let's Encrypt
echo "Installing SSL with Let's Encrypt..."
sudo certbot --apache -d $DOMAIN_NAME --non-interactive --agree-tos -m admin@$DOMAIN_NAME

# Konfigurasi WordPress untuk HTTPS
echo "Configuring WordPress to use HTTPS..."
sudo bash -c 'echo "define(\"FORCE_SSL_ADMIN\", true);" >> /var/www/html/wp-config.php'
sudo bash -c 'echo "define(\"WP_HOME\", \"https://$DOMAIN_NAME\");" >> /var/www/html/wp-config.php'
sudo bash -c 'echo "define(\"WP_SITEURL\", \"https://$DOMAIN_NAME\");" >> /var/www/html/wp-config.php'

# Instalasi WordPress CLI untuk setup admin
echo "Installing WP-CLI..."
cd /usr/local/bin
sudo curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
sudo chmod +x wp-cli.phar
sudo mv wp-cli.phar wp

# Setup Admin WordPress dengan WP-CLI
echo "Setting up WordPress Admin..."
cd /var/www/html
sudo -u www-data wp core install --url="https://$DOMAIN_NAME" --title="Aksyanet VPN" --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASSWORD" --admin_email="admin@$DOMAIN_NAME"

# Restart Apache agar SSL aktif
echo "Restarting Apache..."
sudo systemctl restart apache2

echo "Installation Complete!"
echo "WordPress is available at: https://$DOMAIN_NAME/"
echo "WordPress Admin: Username: $WP_ADMIN_USER, Password: $WP_ADMIN_PASSWORD"
echo "ZeroTier Controller is now running on your VPS."
echo "ZeroTier Network ID: $NETWORK_ID"
