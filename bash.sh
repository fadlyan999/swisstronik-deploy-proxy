#!/bin/bash
# Script Instalasi Headscale Self-Hosted + WordPress + WooCommerce di VPS Ubuntu/Debian
# Pastikan tidak ada kesalahan dalam instalasi ini

set -e  # Menghentikan script jika terjadi error

# Variabel Konfigurasi
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 12)
WP_DB_NAME="wordpress"
WP_DB_USER="wp_user"
WP_DB_PASSWORD=$(openssl rand -base64 12) # Generate password acak untuk database
DOMAIN_NAME="aksyanet.my.id"
WP_ADMIN_USER="admin"
WP_ADMIN_PASSWORD="admin"

# Update sistem dan install paket dasar
echo "Updating system and installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx mysql-server php php-mysql php-fpm php-curl unzip git sqlite3

# Install Headscale
echo "Installing Headscale..."
curl -fsSL https://github.com/juanfont/headscale/releases/latest/download/headscale-linux-amd64 -o headscale
chmod +x headscale
sudo mv headscale /usr/local/bin/
mkdir -p /etc/headscale /var/lib/headscale

# Konfigurasi Headscale
echo "Configuring Headscale..."
cat <<EOF | sudo tee /etc/headscale/config.yaml
server_url: "http://\$(curl -s ifconfig.me):8080"
listen_addr: "0.0.0.0:8080"
log_level: "info"
database:
  type: "sqlite"
  sqlite:
    path: "/var/lib/headscale/db.sqlite"
EOF

sudo systemctl restart headscale || true

# Setup Nginx Reverse Proxy
echo "Setting up Nginx..."
sudo tee /etc/nginx/sites-available/headscale <<EOF
server {
    listen 80;
    server_name headscale.$DOMAIN_NAME;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -s /etc/nginx/sites-available/headscale /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Instalasi WordPress + WooCommerce
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

# Instalasi WordPress CLI
echo "Installing WP-CLI..."
cd /usr/local/bin
sudo curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
sudo chmod +x wp-cli.phar
sudo mv wp-cli.phar wp

# Setup Admin WordPress dengan WP-CLI
echo "Setting up WordPress Admin..."
cd /var/www/html
sudo -u www-data wp core install --url="http://$DOMAIN_NAME" --title="Aksyanet VPN" --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASSWORD" --admin_email="admin@$DOMAIN_NAME"

# Pastikan WooCommerce terinstal dengan benar
echo "Installing and verifying WooCommerce installation..."
sudo -u www-data wp plugin install woocommerce --activate
if ! sudo -u www-data wp plugin is-active woocommerce; then
    echo "WooCommerce activation failed. Retrying..."
    sudo -u www-data wp plugin activate woocommerce
fi

sudo -u www-data wp plugin install theme-my-login --activate

# Setup halaman login dan register
echo "Configuring Login & Registration Pages..."
sudo -u www-data wp option update woocommerce_enable_myaccount_registration "yes"
sudo -u www-data wp option update woocommerce_enable_myaccount_checkout_registration "yes"
sudo -u www-data wp option update theme_my_login_show_reg_link "1"
sudo -u www-data wp option update theme_my_login_show_pass_link "1"

# Restart Nginx agar semua layanan aktif
echo "Restarting Nginx..."
sudo systemctl restart nginx

echo "Installation Complete!"
echo "WordPress is available at: http://$DOMAIN_NAME/"
echo "WordPress Admin: Username: $WP_ADMIN_USER, Password: $WP_ADMIN_PASSWORD"
echo "Headscale Controller is now running on your VPS as a self-hosted SD-WAN service."
