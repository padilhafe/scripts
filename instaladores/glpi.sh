#!/bin/bash
# Script de Instalação do GLPI 10 no Ubuntu/Debian - Instalação Interativa

set -e

# -----------------------------
# Cores para output
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------
# Funções auxiliares
# -----------------------------
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Instalação do GLPI 10${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Função para validar entrada não vazia
validate_input() {
    local input="$1"
    local field_name="$2"
    
    if [[ -z "$input" ]]; then
        print_error "O campo '$field_name' não pode estar vazio!"
        return 1
    fi
    return 0
}

# Função para validar porta
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Porta inválida! Deve ser um número entre 1 e 65535."
        return 1
    fi
    return 0
}

# Função para validar senha
validate_password() {
    local password="$1"
    if [ ${#password} -lt 8 ]; then
        print_error "A senha deve ter pelo menos 8 caracteres!"
        return 1
    fi
    return 0
}

# Função para detectar IP da primeira interface de rede
get_network_ip() {
    local ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    if [[ -z "$ip" ]]; then
        # Fallback para outros métodos
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]]; then
        # Fallback para ifconfig
        ip=$(ifconfig 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -1)
    fi
    echo "$ip"
}

# -----------------------------
# Função para verificar variáveis existentes
# -----------------------------
check_existing_vars() {
    local existing_vars=()
    
    if [[ -n "${GLPI_DB:-}" ]]; then
        existing_vars+=("GLPI_DB=$GLPI_DB")
    fi
    if [[ -n "${GLPI_DB_USER:-}" ]]; then
        existing_vars+=("GLPI_DB_USER=$GLPI_DB_USER")
    fi
    if [[ -n "${GLPI_DB_PASSWORD:-}" ]]; then
        existing_vars+=("GLPI_DB_PASSWORD=***")
    fi
    if [[ -n "${SERVER_NAME:-}" ]]; then
        existing_vars+=("SERVER_NAME=$SERVER_NAME")
    fi
    if [[ -n "${SERVER_PORT:-}" ]]; then
        existing_vars+=("SERVER_PORT=$SERVER_PORT")
    fi
    
    if [[ ${#existing_vars[@]} -gt 0 ]]; then
        echo -e "${BLUE}Variáveis de ambiente encontradas:${NC}"
        for var in "${existing_vars[@]}"; do
            echo "  • $var"
        done
        echo
        return 0
    fi
    return 1
}

# Função para confirmar uso de variáveis existentes
confirm_existing_vars() {
    while true; do
        read -p "Deseja usar essas configurações? [S/n]: " confirm
        case $confirm in
            [Ss]* | "" ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Por favor, responda 's' para sim ou 'n' para não.";;
        esac
    done
}

# -----------------------------
# Coleta de configurações interativas
# -----------------------------
print_header

echo -e "${YELLOW}Este script irá instalar o GLPI 10 no seu sistema.${NC}"

# Detectar IP da rede
network_ip=$(get_network_ip)
if [[ -n "$network_ip" ]]; then
    print_info "IP da rede detectado: $network_ip"
fi

# Verificar se há variáveis de ambiente já definidas
if check_existing_vars; then
    if confirm_existing_vars; then
        print_info "Usando configurações existentes das variáveis de ambiente."
        # Definir valores padrão para variáveis não definidas
        GLPI_DB=${GLPI_DB:-glpi_db}
        GLPI_DB_HOST="localhost"
        GLPI_DB_USER=${GLPI_DB_USER:-glpi_user}
        SERVER_NAME=${SERVER_NAME:-$network_ip}
        SERVER_PORT=${SERVER_PORT:-80}
        HTTPS_ENABLED="Off"
        
        # Verificar se a senha está definida
        if [[ -z "${GLPI_DB_PASSWORD:-}" ]]; then
            print_warning "Senha do banco de dados não encontrada nas variáveis de ambiente."
            while true; do
                read -s -p "Senha do banco de dados GLPI: " GLPI_DB_PASSWORD
                echo
                if validate_password "$GLPI_DB_PASSWORD"; then
                    read -s -p "Confirme a senha: " GLPI_DB_PASSWORD_CONFIRM
                    echo
                    if [ "$GLPI_DB_PASSWORD" = "$GLPI_DB_PASSWORD_CONFIRM" ]; then
                        break
                    else
                        print_error "As senhas não coincidem!"
                    fi
                fi
            done
        fi
    else
        print_info "Redefinindo todas as configurações."
        echo
    fi
fi

# Se não há variáveis ou usuário escolheu redefinir, coletar todas as informações
if [[ -z "${GLPI_DB:-}" ]] || [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Por favor, forneça as seguintes informações:${NC}"
    echo

    # Nome do banco de dados
    while true; do
        read -p "Nome do banco de dados GLPI [glpi_db]: " GLPI_DB
        GLPI_DB=${GLPI_DB:-glpi_db}
        if validate_input "$GLPI_DB" "Nome do banco de dados"; then
            break
        fi
    done

    # Host do banco de dados (sempre localhost)
    GLPI_DB_HOST="localhost"

    # Usuário do banco de dados
    while true; do
        read -p "Usuário do banco de dados GLPI [glpi_user]: " GLPI_DB_USER
        GLPI_DB_USER=${GLPI_DB_USER:-glpi_user}
        if validate_input "$GLPI_DB_USER" "Usuário do banco de dados"; then
            break
        fi
    done

    # Senha do banco de dados
    while true; do
        read -s -p "Senha do banco de dados GLPI: " GLPI_DB_PASSWORD
        echo
        if validate_password "$GLPI_DB_PASSWORD"; then
            read -s -p "Confirme a senha: " GLPI_DB_PASSWORD_CONFIRM
            echo
            if [ "$GLPI_DB_PASSWORD" = "$GLPI_DB_PASSWORD_CONFIRM" ]; then
                break
            else
                print_error "As senhas não coincidem!"
            fi
        fi
    done

    # Nome do servidor/domínio
    detected_ip=$(get_network_ip)
    default_server=${detected_ip:-localhost}
    while true; do
        read -p "Nome do servidor/domínio [$default_server]: " SERVER_NAME
        SERVER_NAME=${SERVER_NAME:-$default_server}
        if validate_input "$SERVER_NAME" "Nome do servidor"; then
            break
        fi
    done

    # Porta do servidor
    while true; do
        read -p "Porta do servidor web [80]: " SERVER_PORT
        SERVER_PORT=${SERVER_PORT:-80}
        if validate_port "$SERVER_PORT"; then
            break
        fi
    done

    # HTTPS (desabilitado por padrão)
    HTTPS_ENABLED="Off"
fi

echo
print_info "Configurações coletadas:"
echo "  • Banco de dados: $GLPI_DB"
echo "  • Usuário: $GLPI_DB_USER"
echo "  • Servidor: $SERVER_NAME"
echo "  • Porta: $SERVER_PORT"
echo "  • HTTPS: $HTTPS_ENABLED"
echo

# Confirmação final
while true; do
    read -p "Deseja continuar com a instalação? [s/N]: " confirm
    case $confirm in
        [Ss]* ) break;;
        [Nn]* ) echo "Instalação cancelada."; exit 0;;
        * ) echo "Por favor, responda 's' para sim ou 'n' para não.";;
    esac
done

echo
print_info "Iniciando instalação..."

# -----------------------------
# Detectar SO e versão
# -----------------------------
print_info "Detectando sistema operacional..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
    print_success "Sistema detectado: $OS_NAME $OS_VERSION"
else
    print_error "Não foi possível detectar o sistema operacional."
    exit 1
fi

# Suporte apenas Ubuntu e Debian
if [[ "$OS_NAME" != "debian" ]]; then
    print_error "Sistema não suportado: $OS_NAME"
    print_info "Este script suporta apenas Debian."
    exit 1
fi

# -----------------------------
# Atualizar sistema
# -----------------------------
print_info "Atualizando sistema..."
if sudo apt update -q -y && sudo apt upgrade -q -y; then
    print_success "Sistema atualizado com sucesso"
else
    print_error "Falha ao atualizar o sistema"
    exit 1
fi

# -----------------------------
# Preparar o banco de dados
# -----------------------------
print_info "Instalando MariaDB..."
if sudo apt install -q -y mariadb-server mysql-common; then
    print_success "MariaDB instalado com sucesso"
else
    print_error "Falha ao instalar MariaDB"
    exit 1
fi

# Configurar MariaDB de forma segura
print_info "Configurando MariaDB..."
if sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${GLPI_DB_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
then
    print_success "MariaDB configurado com sucesso"
else
    print_error "Falha ao configurar MariaDB"
    exit 1
fi

# Carregar timezone data
print_info "Carregando dados de timezone..."
if mariadb-tzinfo-to-sql /usr/share/zoneinfo | sudo mysql -u root -p${GLPI_DB_PASSWORD} mysql; then
    print_success "Dados de timezone carregados com sucesso"
else
    print_error "Falha ao carregar dados de timezone"
    exit 1
fi

# Configurar banco de dados GLPI
print_info "Criando banco de dados e usuário GLPI..."
if sudo mysql -u root -p${GLPI_DB_PASSWORD} <<EOF
CREATE DATABASE IF NOT EXISTS \`${GLPI_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${GLPI_DB_USER}'@'${GLPI_DB_HOST}' IDENTIFIED BY '${GLPI_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${GLPI_DB}\`.* TO '${GLPI_DB_USER}'@'${GLPI_DB_HOST}';
GRANT SELECT ON mysql.time_zone_name TO '${GLPI_DB_USER}'@'${GLPI_DB_HOST}';
FLUSH PRIVILEGES;
EOF
then
    print_success "Banco de dados e usuário criados com sucesso"
else
    print_error "Falha ao criar banco de dados e usuário"
    exit 1
fi

print_info "Iniciando e habilitando MariaDB..."
if sudo systemctl enable mariadb && sudo systemctl start mariadb; then
    print_success "MariaDB iniciado e habilitado com sucesso"
else
    print_error "Falha ao iniciar MariaDB"
    exit 1
fi

# -----------------------------
# Preparando o Sistema Operacional
# -----------------------------
print_info "Instalando dependências do sistema..."
if sudo apt install -q -y \
	apache2 \
	mariadb-client \
	aptitude \
	wget \
	lsb-release \
	ca-certificates \
	apt-transport-https \
	gnupg \
	libkrb5-dev \
	build-essential; then
    print_success "Dependências do sistema instaladas com sucesso"
else
    print_error "Falha ao instalar dependências do sistema"
    exit 1
fi

print_info "Instalando PHP e extensões..."
if sudo apt install -q -y php php-{apcu,cli,common,curl,gd,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2} libapache2-mod-php php-soap php-cas php-pear php-dev; then
    print_success "PHP e extensões instalados com sucesso"
else
    print_error "Falha ao instalar PHP e extensões"
    exit 1
fi

print_info "Configurando repositório PHP Sury..."
if wget -qO- https://packages.sury.org/php/README.txt | sudo bash -x >/dev/null 2>&1; then
    print_success "Repositório PHP Sury configurado com sucesso"
else
    print_error "Falha ao configurar repositório PHP Sury"
    exit 1
fi

print_info "Atualizando sistema com novos repositórios..."
if sudo aptitude update >/dev/null 2>&1 && sudo aptitude safe-upgrade -y >/dev/null 2>&1; then
    print_success "Sistema atualizado com novos repositórios"
else
    print_error "Falha ao atualizar sistema"
    exit 1
fi

print_info "Instalando dependências para IMAP..."
if sudo aptitude install -y libc-client-dev >/dev/null 2>&1; then
    print_success "Dependências IMAP instaladas com sucesso"
else
    print_error "Falha ao instalar dependências IMAP"
    exit 1
fi

print_info "Atualizando PECL e instalando extensão IMAP..."
if sudo pecl channel-update pecl.php.net >/dev/null 2>&1 && yes | sudo pecl install imap >/dev/null 2>&1; then
    print_success "Extensão IMAP instalada com sucesso"
else
    print_error "Falha ao instalar extensão IMAP"
    exit 1
fi

# -----------------------------
# Configurações do PHP
# -----------------------------
print_info "Configurando PHP..."
PHP_INI="/etc/php/8.4/apache2/php.ini"

if echo "extension=imap.so" | sudo tee /etc/php/8.4/mods-available/imap.ini >/dev/null 2>&1 && \
   sudo sed -i 's/^memory_limit = .*$/memory_limit = 256M/' "$PHP_INI" && \
   sudo sed -i 's/^post_max_size = .*$/post_max_size = 20M/' "$PHP_INI" && \
   sudo sed -i 's/^upload_max_filesize = .*$/upload_max_filesize = 20M/' "$PHP_INI" && \
   sudo sed -i 's/^max_execution_time = .*$/max_execution_time = 60/' "$PHP_INI" && \
   sudo sed -i 's/^max_input_vars = .*$/max_input_vars = 5000/' "$PHP_INI" && \
   sudo sed -i "s/^session.cookie_secure =.*$/session.cookie_secure = $HTTPS_ENABLED/" "$PHP_INI" && \
   sudo sed -i "s/^session.cookie_httponly =.*$/session.cookie_httponly = On/" "$PHP_INI" && \
   sudo sed -i 's/^session.cookie_samesite =.*$/session.cookie_samesite = Lax/' "$PHP_INI" && \
   sudo sed -i 's|^;date.timezone =.*$|date.timezone = America/Sao_Paulo|' "$PHP_INI"; then
    print_success "PHP configurado com sucesso"
else
    print_error "Falha ao configurar PHP"
    exit 1
fi

# -----------------------------
# Download e Configuração do GLPI
# -----------------------------
print_info "Baixando GLPI 10.0.20..."
cd /var/www/html
if sudo wget --quiet --show-progress https://github.com/glpi-project/glpi/releases/download/10.0.20/glpi-10.0.20.tgz; then
    print_success "GLPI baixado com sucesso"
else
    print_error "Falha ao baixar GLPI"
    exit 1
fi

print_info "Extraindo arquivos do GLPI..."
if sudo tar -xzf glpi-10.0.20.tgz && sudo rm glpi-10.0.20.tgz; then
    print_success "GLPI extraído com sucesso"
else
    print_error "Falha ao extrair GLPI"
    exit 1
fi

print_info "Configurando arquivos do GLPI..."
if sudo tee /var/www/html/glpi/inc/downstream.php > /dev/null <<'EOF'
<?php

define('GLPI_CONFIG_DIR', '/etc/glpi/');

if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
require_once GLPI_CONFIG_DIR . '/local_define.php';
}

EOF
then
    print_success "Arquivo downstream.php criado com sucesso"
else
    print_error "Falha ao criar arquivo downstream.php"
    exit 1
fi

print_info "Movendo diretórios do GLPI..."
if sudo mv /var/www/html/glpi/config /etc/glpi && \
   sudo mv /var/www/html/glpi/files /var/lib/glpi && \
   sudo mv /var/lib/glpi/_log /var/log/glpi; then
    print_success "Diretórios movidos com sucesso"
else
    print_error "Falha ao mover diretórios"
    exit 1
fi

print_info "Criando arquivo de configuração local..."
if sudo tee /etc/glpi/local_define.php > /dev/null <<'EOF'
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
then
    print_success "Arquivo de configuração local criado com sucesso"
else
    print_error "Falha ao criar arquivo de configuração local"
    exit 1
fi

# -----------------------------
# Configuração do Apache
# -----------------------------
print_info "Configurando Apache..."
if sudo tee /etc/apache2/sites-available/glpi.conf > /dev/null <<EOF
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
then
    print_success "Apache configurado com sucesso"
else
    print_error "Falha ao configurar Apache"
    exit 1
fi

print_info "Instalando banco de dados GLPI..."
cd /var/www/html/glpi
if yes | sudo php bin/console db:install --db-host=${GLPI_DB_HOST} --db-name=${GLPI_DB} --db-user=${GLPI_DB_USER} --db-password=${GLPI_DB_PASSWORD} >/dev/null 2>&1; then
    print_success "Banco de dados GLPI instalado com sucesso"
else
    print_error "Falha ao instalar banco de dados GLPI"
    exit 1
fi

# -----------------------------
# Finalizando Instalação
# -----------------------------
print_info "Finalizando configuração..."
if sudo phpenmod imap && \
   sudo a2dissite 000-default.conf >/dev/null 2>&1 && \
   sudo a2enmod rewrite && \
   sudo a2ensite glpi.conf && \
   sudo systemctl restart apache2; then
    print_success "Apache configurado e reiniciado com sucesso"
else
    print_error "Falha ao configurar Apache"
    exit 1
fi

print_info "Configurando permissões..."
if sudo chown www-data:www-data /var/www/html/glpi/ -R && \
   sudo chown www-data:www-data /etc/glpi -R && \
   sudo chown www-data:www-data /var/lib/glpi -R && \
   sudo chown www-data:www-data /var/log/glpi -R && \
   sudo chown www-data:www-data /var/www/html/glpi/marketplace -Rf && \
   sudo find /var/www/html/glpi/ -type f -exec chmod 0644 {} \; && \
   sudo find /var/www/html/glpi/ -type d -exec chmod 0755 {} \; && \
   sudo find /etc/glpi -type f -exec chmod 0644 {} \; && \
   sudo find /etc/glpi -type d -exec chmod 0755 {} \; && \
   sudo find /var/lib/glpi -type f -exec chmod 0644 {} \; && \
   sudo find /var/lib/glpi -type d -exec chmod 0755 {} \; && \
   sudo find /var/log/glpi -type f -exec chmod 0644 {} \; && \
   sudo find /var/log/glpi -type d -exec chmod 0755 {} \; >/dev/null 2>&1; then
    print_success "Permissões configuradas com sucesso"
else
    print_error "Falha ao configurar permissões"
    exit 1
fi

# -----------------------------
# Verificar status dos serviços
# -----------------------------
print_info "Verificando status dos serviços..."
if systemctl is-active --quiet apache2 && \
   systemctl is-active --quiet mariadb; then
    print_success "Todos os serviços estão rodando"
else
    print_warning "Alguns serviços podem não estar rodando corretamente"
fi

echo
print_success "Instalação concluída com sucesso!"
echo
print_info "Informações de acesso:"
echo "  • URL: http://${SERVER_NAME}:${SERVER_PORT}"
echo "  • Usuário padrão: glpi"
echo "  • Senha padrão: glpi"
echo
print_warning "IMPORTANTE: Altere a senha padrão após o primeiro login!"
echo
print_info "Para verificar o status dos serviços, execute:"
echo "  sudo systemctl status apache2 mariadb"
