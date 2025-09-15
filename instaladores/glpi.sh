#!/bin/bash
# Script de Instalação do GLPI 10 no Debian 13 - Instalação Centralizada

set -e

# -----------------------------
# Variáveis de Configuração
# -----------------------------
GLPI_DB=${GLPI_DB:-glpi_db}
GLPI_DB_HOST=${GLPI_DB_HOST:-localhost}
GLPI_DB_USER=${GLPI_DB_USER:-glpi_user}
GLPI_DB_PASSWORD=${GLPI_DB_PASSWORD:-glpi_password}
GLPI_HOST=${GLPI_HOST:-localhost}
SERVER_NAME=${SERVER_NAME:-127.0.0.1}
SERVER_PORT=${SERVER_PORT:-80}
PHP_INI=${PHP_INI:-/etc/php/8.4/apache2/php.ini}
HTTPS_ENABLED=${HTTPS_ENABLED:-Off}

# -----------------------------
# Detectar SO e versão
# -----------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
else
    echo "Não foi possível detectar o sistema operacional."
    exit 1
fi

# Suporte apenas Ubuntu e Debian
if [[ "$OS_NAME" != "debian" ]]; then
    echo "Sistema não suportado: $OS_NAME"
    exit 1
fi

# -----------------------------
# Atualizar sistema
# -----------------------------
sudo apt update -y && sudo apt upgrade -y

# -----------------------------
# Preparar o banco de dados
# -----------------------------
sudo apt install -y mariadb-server mysql-common

# Configurar MariaDB de forma segura
sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${GLPI_DB_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# Carregar timezone data
mariadb-tzinfo-to-sql /usr/share/zoneinfo | sudo mysql -u root -p${GLPI_DB_PASSWORD} mysql

# Configurar banco de dados GLPI
sudo mysql -u root -p${GLPI_DB_PASSWORD} <<EOF
CREATE DATABASE IF NOT EXISTS \`${GLPI_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${GLPI_DB_USER}'@'${GLPI_HOST}' IDENTIFIED BY '${GLPI_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${GLPI_DB}\`.* TO '${GLPI_DB_USER}'@'${GLPI_HOST}';
GRANT SELECT ON mysql.time_zone_name TO '${GLPI_DB_USER}'@'${GLPI_HOST}';
FLUSH PRIVILEGES;
EOF


sudo systemctl enable mariadb
sudo systemctl start mariadb

# -----------------------------
# Preparando o Sistema Operacional
# -----------------------------
sudo apt install -y \
	apache2 \
	mariadb-client \
	aptitude \
	wget \
	lsb-release \
	ca-certificates \
	apt-transport-https \
	gnupg \
	libkrb5-dev \
	build-essential

sudo apt install -y php php-{apcu,cli,common,curl,gd,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2} libapache2-mod-php php-soap php-cas php-pear php-dev

wget -qO- https://packages.sury.org/php/README.txt | sudo bash -x
sudo aptitude update
sudo aptitude safe-upgrade -y
sudo aptitude install -y libc-client-dev
sudo pecl channel-update pecl.php.net
yes | sudo pecl install imap

# -----------------------------
# Configurações do PHP
# -----------------------------
echo "extension=imap.so" | sudo tee /etc/php/8.4/mods-available/imap.ini
sudo sed -i 's/^memory_limit = .*$/memory_limit = 256M/' "$PHP_INI"
sudo sed -i 's/^post_max_size = .*$/post_max_size = 20M/' "$PHP_INI"
sudo sed -i 's/^upload_max_filesize = .*$/upload_max_filesize = 20M/' "$PHP_INI"
sudo sed -i 's/^max_execution_time = .*$/max_execution_time = 60/' "$PHP_INI"
sudo sed -i 's/^max_input_vars = .*$/max_input_vars = 5000/' "$PHP_INI"
sudo sed -i "s/^session.cookie_secure =.*$/session.cookie_secure = $HTTPS_ENABLED/" "$PHP_INI"
sudo sed -i "s/^session.cookie_httponly =.*$/session.cookie_httponly = On/" "$PHP_INI"
sudo sed -i 's/^session.cookie_samesite =.*$/session.cookie_samesite = Lax/' "$PHP_INI"
sudo sed -i 's|^;date.timezone =.*$|date.timezone = America/Sao_Paulo|' "$PHP_INI"

# -----------------------------
# Download e Configuração do GLPI
# -----------------------------
cd /var/www/html
sudo wget https://github.com/glpi-project/glpi/releases/download/10.0.20/glpi-10.0.20.tgz
sudo tar -xvzf glpi-10.0.20.tgz
sudo rm glpi-10.0.20.tgz

sudo tee /var/www/html/glpi/inc/downstream.php > /dev/null <<'EOF'
<?php

define('GLPI_CONFIG_DIR', '/etc/glpi/');

if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
require_once GLPI_CONFIG_DIR . '/local_define.php';
}

EOF

sudo mv /var/www/html/glpi/config /etc/glpi
sudo mv /var/www/html/glpi/files /var/lib/glpi
sudo mv /var/lib/glpi/_log /var/log/glpi

sudo tee /etc/glpi/local_define.php > /dev/null <<'EOF'
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_DOC_DIR', GLPI_VAR_DIR);
define('GLPI_CACHE_DIR', GLPI_VAR_DIR . '/_cache');
define('GLPI_CRON_DIR', GLPI_VAR_DIR . '/_cron');
define('GLPI_GRAPH_DIR', GLPI_VAR_DIR . '/_graphs');
define('GLPI_LOCAL_I18N_DIR', GLPI_VAR_DIR . '/_locales');
define('GLPI_LOCK_DIR', GLPI_VAR_DIR . '/_lock');
define('GLPI_PICTURE_DIR', GLPI_VAR_DIR . '/_pictures');
define('GLPI_PLUGIN_DOC_DIR', GLPI_VAR_DIR . '/_plugins');
define('GLPI_RSS_DIR', GLPI_VAR_DIR . '/_rss');
define('GLPI_SESSION_DIR', GLPI_VAR_DIR . '/_sessions');
define('GLPI_TMP_DIR', GLPI_VAR_DIR . '/_tmp');
define('GLPI_UPLOAD_DIR', GLPI_VAR_DIR . '/_uploads');
define('GLPI_INVENTORY_DIR', GLPI_VAR_DIR . '/_inventories');
define('GLPI_THEMES_DIR', GLPI_VAR_DIR . '/_themes');
define('GLPI_LOG_DIR', '/var/log/glpi');

EOF

# -----------------------------
# Configuração do Apache
# -----------------------------
sudo tee /etc/apache2/sites-available/glpi.conf > /dev/null <<EOF
<VirtualHost *:${SERVER_PORT}>
    ServerName ${SERVER_NAME}
    DocumentRoot /var/www/html/glpi/public

    <Directory /var/www/html/glpi/public>
        Require all granted
        RewriteEngine On

        # Passar autenticação HTTP para o PHP
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

        # Redirecionar requisições para index.php
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>

EOF

cd /var/www/html/glpi
yes | sudo php bin/console db:install --db-host=${GLPI_DB_HOST} --db-name=${GLPI_DB} --db-user=${GLPI_DB_USER} --db-password=${GLPI_DB_PASSWORD}

# -----------------------------
# Finalizando Instalação
# -----------------------------
sudo phpenmod imap
sudo a2dissite 000-default.conf || true
sudo a2enmod rewrite
sudo a2ensite glpi.conf
sudo systemctl restart apache2

sudo chown www-data:www-data /var/www/html/glpi/ -R
sudo chown www-data:www-data /etc/glpi -R
sudo chown www-data:www-data /var/lib/glpi -R
sudo chown www-data:www-data /var/log/glpi -R
sudo chown www-data:www-data /var/www/html/glpi/marketplace -Rf
sudo find /var/www/html/glpi/ -type f -exec chmod 0644 {} \;
sudo find /var/www/html/glpi/ -type d -exec chmod 0755 {} \;
sudo find /etc/glpi -type f -exec chmod 0644 {} \;
sudo find /etc/glpi -type d -exec chmod 0755 {} \;
sudo find /var/lib/glpi -type f -exec chmod 0644 {} \;
sudo find /var/lib/glpi -type d -exec chmod 0755 {} \;
sudo find /var/log/glpi -type f -exec chmod 0644 {} \;
sudo find /var/log/glpi -type d -exec chmod 0755 {} \;
