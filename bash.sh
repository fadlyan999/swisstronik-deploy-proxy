#!/bin/bash
# Script Otomatis Install Headscale + WordPress + WooCommerce + Dashboard Pelanggan
# Pastikan dijalankan di VPS dengan Ubuntu 22.04

set -e  # Hentikan jika ada error

# === 1. Update Sistem ===
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# === 2. Instalasi Dependensi ===
echo "Installing dependencies..."
sudo apt install -y curl unzip git nginx mysql-server php php-fpm php-mysql php-curl php-xml php-mbstring php-zip

# === 3. Instalasi Headscale ===
echo "Installing Headscale..."
curl -fsSL https://github.com/juanfont/headscale/releases/latest/download/headscale-linux-amd64 -o headscale
chmod +x headscale
sudo mv headscale /usr/local/bin/
mkdir -p /etc/headscale /var/lib/headscale

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

# === 4. Setup Nginx Reverse Proxy ===
echo "Setting up Nginx..."
sudo tee /etc/nginx/sites-available/headscale <<EOF
server {
    listen 80;
    server_name headscale.yourdomain.com;
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

# === 5. Instalasi WordPress ===
echo "Installing WordPress..."
cd /var/www/
sudo rm -rf html && sudo mkdir html
cd html
sudo curl -O https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz --strip-components=1
sudo chown -R www-data:www-data /var/www/html

# === 6. Setup Database WordPress ===
echo "Configuring MySQL..."
DB_PASS=$(openssl rand -base64 16)
sudo mysql -e "CREATE DATABASE wordpress;"
sudo mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# === 7. Konfigurasi WordPress ===
cat <<EOF | sudo tee /var/www/html/wp-config.php
<?php
define('DB_NAME', 'wordpress');
define('DB_USER', 'wpuser');
define('DB_PASSWORD', '$DB_PASS');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');
define('WP_DEBUG', false);
EOF

# === 8. Install WooCommerce ===
echo "Installing WooCommerce..."
sudo -u www-data wp core install --path=/var/www/html --url="http://yourdomain.com" --title="SD-WAN Service" --admin_user="admin" --admin_password="admin" --admin_email="admin@yourdomain.com"
sudo -u www-data wp plugin install woocommerce --activate --path=/var/www/html

# === 9. Setup User Registration + Dashboard ===
echo "Setting up User Dashboard..."
cat <<EOF | sudo tee /var/www/html/wp-content/plugins/headscale-dashboard.php
<?php
/**
 * Plugin Name: Headscale Dashboard
 * Description: Dashboard untuk pelanggan mengelola SD-WAN mereka.
 */
if (!defined('ABSPATH')) exit;
function headscale_dashboard() {
    if (!is_user_logged_in()) return "<p>Silakan login untuk melihat dashboard Anda.</p>";
    \$user = wp_get_current_user();
    \$username = sanitize_user(explode('@', \$user->user_email)[0]);
    \$device_list = shell_exec("headscale -u \$username nodes list | grep 'Name:' | awk '{print \$2}'");
    return "<h3>Perangkat Terdaftar:</h3><pre>\$device_list</pre>";
}
add_shortcode('headscale_devices', 'headscale_dashboard');
?>
EOF

sudo systemctl restart nginx

echo "Installation Completed! Access your WordPress at http://yourdomain.com and configure WooCommerce payment gateway. Database password is stored securely."
