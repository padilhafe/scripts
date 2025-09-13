#!/bin/bash
# Script de Instalação do Zabbix 7 no Ubuntu/Debian - Instalação Centralizada

set -e

# -----------------------------
# Variáveis de configuração
# -----------------------------
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASSWORD="senha_segura"
SERVER_NAME="seu_dominio"
SERVER_PORT="80"
TIMEZONE="America/Sao_Paulo"

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
if [[ "$OS_NAME" != "ubuntu" && "$OS_NAME" != "debian" ]]; then
    echo "Sistema não suportado: $OS_NAME"
    exit 1
fi

# Formata versão para o pacote do Zabbix
if [ "$OS_NAME" = "ubuntu" ]; then
    PACKAGE_VERSION="$OS_VERSION"
elif [ "$OS_NAME" = "debian" ]; then
    PACKAGE_VERSION="${OS_VERSION%%.*}"
fi

# -----------------------------
# Atualizar sistema
# -----------------------------
sudo apt update -y && sudo apt upgrade -y

# -----------------------------
# Instalar MariaDB
# -----------------------------
sudo apt install -y mariadb-server mariadb-client

# -----------------------------
# Configurar MariaDB
# -----------------------------
sudo mariadb-secure-installation <<EOF

n
y
$ZABBIX_DB_PASSWORD
$ZABBIX_DB_PASSWORD
y
y
y
y
EOF

# Criar banco de dados e usuário Zabbix
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${ZABBIX_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${ZABBIX_DB}\`.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# -----------------------------
# Instalar repositório do Zabbix
# -----------------------------
ZABBIX_BASE_URL="https://repo.zabbix.com/zabbix/7.0/${OS_NAME}/pool/main/z/zabbix-release"
PACKAGE_NAME="zabbix-release_latest+${OS_NAME}${PACKAGE_VERSION}_all.deb"
DOWNLOAD_URL="${ZABBIX_BASE_URL}/${PACKAGE_NAME}"

echo "Baixando Zabbix release para $OS_NAME $OS_VERSION..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$PACKAGE_NAME"

sudo dpkg -i "$PACKAGE_NAME"
rm "$PACKAGE_NAME"
sudo apt update -y

# -----------------------------
# Instalar pacotes do Zabbix
# -----------------------------
sudo apt install -y \
    zabbix-server-mysql \
    zabbix-frontend-php \
    zabbix-nginx-conf \
    zabbix-agent \
    zabbix-sql-scripts

# -----------------------------
# Configurar Zabbix server e Nginx
# -----------------------------
sudo sed -i "s/^#\s*\(DBPassword=\).*/\1${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sudo sed -i -E "s@#(\s*listen\s+)8080;@\1${SERVER_PORT};@" /etc/zabbix/nginx.conf
sudo sed -i -E "s@#(\s*server_name\s+)example.com;@\1${SERVER_NAME};@" /etc/zabbix/nginx.conf
echo "php_value[date.timezone] = ${TIMEZONE}" | sudo tee -a /etc/zabbix/php-fpm.conf

# -----------------------------
# Popular banco de dados Zabbix
# -----------------------------
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
mysql --default-character-set=utf8mb4 -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASSWORD}" "${ZABBIX_DB}"

# -----------------------------
# Reiniciar e habilitar serviços
# -----------------------------
sudo systemctl restart zabbix-server zabbix-agent nginx php*-fpm
sudo systemctl enable zabbix-server zabbix-agent nginx php*-fpm

echo "Instalação concluída! Acesse http://${SERVER_NAME}:${SERVER_PORT} para continuar a configuração via interface web."
