#!/bin/bash
# Script Instalasi ZeroTier Self-Hosted Controller + WordPress + WooCommerce di VPS Ubuntu/Debian
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
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php php-curl curl unzip git -y

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

# Generate ZeroTier API Token
echo "Fetching ZeroTier API Token..."
ZEROTIER_API_TOKEN=$(sudo cat /var/lib/zerotier-one/authtoken.secret)

# Membuat Network ID Sendiri
echo "Generating Self-Hosted ZeroTier Network..."
sudo zerotier-cli orbit `cat /var/lib/zerotier-one/identity.public` `cat /var/lib/zerotier-one/identity.public`
NETWORK_ID=$(sudo zerotier-cli listnetworks | awk 'NR==2{print $3}')

# Install WordPress + WooCommerce
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

# Instalasi WordPress CLI untuk setup admin
echo "Installing WP-CLI..."
cd /usr/local/bin
sudo curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
sudo chmod +x wp-cli.phar
sudo mv wp-cli.phar wp

# Setup Admin WordPress dengan WP-CLI
echo "Setting up WordPress Admin..."
cd /var/www/html
sudo -u www-data wp core install --url="http://$DOMAIN_NAME" --title="Aksyanet VPN" --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASSWORD" --admin_email="admin@$DOMAIN_NAME"
sudo -u www-data wp plugin install woocommerce --activate
sudo -u www-data wp plugin install theme-my-login --activate

# Setup halaman login dan register
echo "Configuring Login & Registration Pages..."
sudo -u www-data wp option update woocommerce_enable_myaccount_registration "yes"
sudo -u www-data wp option update woocommerce_enable_myaccount_checkout_registration "yes"
sudo -u www-data wp option update theme_my_login_show_reg_link "1"
sudo -u www-data wp option update theme_my_login_show_pass_link "1"

# Instalasi dan Konfigurasi Plugin ZeroTier untuk WooCommerce
echo "Installing ZeroTier WooCommerce Integration Plugin..."
sudo mkdir -p /var/www/html/wp-content/plugins/zerotier-woocommerce
sudo bash -c 'cat <<EOF > /var/www/html/wp-content/plugins/zerotier-woocommerce/zerotier-woocommerce.php
<?php
/**
 * Plugin Name: ZeroTier WooCommerce Integration
 * Description: Plugin untuk menghubungkan WooCommerce dengan ZeroTier VPN secara otomatis.
 * Version: 1.0
 * Author: Aksyanet
 */

defined("ABSPATH") or die("No direct access allowed");

function zerotier_webhook_handler(\$order_id) {
    \$order = wc_get_order(\$order_id);
    if (\$order->get_status() == 'completed') {
        \$networkId = "$NETWORK_ID";
        \$token = "$ZEROTIER_API_TOKEN";
        \$controllerIP = "http://127.0.0.1:9993";
        \$customer_email = \$order->get_billing_email();
        \$nodeId = md5(\$customer_email);
        update_user_meta(\$order->get_user_id(), "zerotier_node_id", \$nodeId);
        \$url = "\$controllerIP/controller/network/\$networkId/member/\$nodeId";
        \$data = json_encode(["config" => ["authorized" => true]]);
        wp_remote_post(\$url, array(
            'method' => 'POST',
            'headers' => array(
                'Authorization' => 'Bearer ' . \$token,
                'Content-Type' => 'application/json'
            ),
            'body' => \$data
        ));
    }
}
add_action('woocommerce_order_status_completed', 'zerotier_webhook_handler');
EOF'

# Restart Apache agar semua layanan aktif
echo "Restarting Apache..."
sudo systemctl restart apache2

echo "Installation Complete!"
echo "WordPress is available at: http://$DOMAIN_NAME/"
echo "WordPress Admin: Username: $WP_ADMIN_USER, Password: $WP_ADMIN_PASSWORD"
echo "ZeroTier Controller is now running on your VPS."
echo "WooCommerce is installed and ZeroTier VPN management is ready!"
echo "Customer Login & Registration is enabled!"
