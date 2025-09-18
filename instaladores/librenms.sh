#!/bin/bash
# Script de Instalação do LibreNMS no Ubuntu/Debian - Instalação Interativa

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
    echo -e "${BLUE}  Instalação do LibreNMS${NC}"
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
    
    if [[ -n "${LIBRENMS_DB:-}" ]]; then
        existing_vars+=("LIBRENMS_DB=$LIBRENMS_DB")
    fi
    if [[ -n "${LIBRENMS_DB_USER:-}" ]]; then
        existing_vars+=("LIBRENMS_DB_USER=$LIBRENMS_DB_USER")
    fi
    if [[ -n "${LIBRENMS_DB_PASSWORD:-}" ]]; then
        existing_vars+=("LIBRENMS_DB_PASSWORD=***")
    fi
    if [[ -n "${SERVER_NAME:-}" ]]; then
        existing_vars+=("SERVER_NAME=$SERVER_NAME")
    fi
    if [[ -n "${SERVER_PORT:-}" ]]; then
        existing_vars+=("SERVER_PORT=$SERVER_PORT")
    fi
    if [[ -n "${SNMP_COMMUNITY:-}" ]]; then
        existing_vars+=("SNMP_COMMUNITY=$SNMP_COMMUNITY")
    fi
    if [[ -n "${TIMEZONE:-}" ]]; then
        existing_vars+=("TIMEZONE=$TIMEZONE")
    fi
    if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
        existing_vars+=("ADMIN_PASSWORD=***")
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

echo -e "${YELLOW}Este script irá instalar o LibreNMS no seu sistema.${NC}"

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
        LIBRENMS_DB=${LIBRENMS_DB:-librenms}
        LIBRENMS_DB_USER=${LIBRENMS_DB_USER:-librenms}
        SERVER_NAME=${SERVER_NAME:-$network_ip}
        SERVER_PORT=${SERVER_PORT:-80}
        SNMP_COMMUNITY=${SNMP_COMMUNITY:-librenms}
        TIMEZONE=${TIMEZONE:-America/Sao_Paulo}
        
        # Verificar se a senha do admin está definida
        if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
            print_warning "Senha do administrador não encontrada nas variáveis de ambiente."
            while true; do
                read -s -p "Senha do administrador LibreNMS: " ADMIN_PASSWORD
                echo
                if validate_password "$ADMIN_PASSWORD"; then
                    read -s -p "Confirme a senha: " ADMIN_PASSWORD_CONFIRM
                    echo
                    if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
                        break
                    else
                        print_error "As senhas não coincidem!"
                    fi
                fi
            done
        fi
        
        # Verificar se a senha está definida
        if [[ -z "${LIBRENMS_DB_PASSWORD:-}" ]]; then
            print_warning "Senha do banco de dados não encontrada nas variáveis de ambiente."
            while true; do
                read -s -p "Senha do banco de dados LibreNMS: " LIBRENMS_DB_PASSWORD
                echo
                if validate_password "$LIBRENMS_DB_PASSWORD"; then
                    read -s -p "Confirme a senha: " LIBRENMS_DB_PASSWORD_CONFIRM
                    echo
                    if [ "$LIBRENMS_DB_PASSWORD" = "$LIBRENMS_DB_PASSWORD_CONFIRM" ]; then
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
if [[ -z "${LIBRENMS_DB:-}" ]] || [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Por favor, forneça as seguintes informações:${NC}"
    echo

    # Nome do banco de dados
    while true; do
        read -p "Nome do banco de dados LibreNMS [librenms]: " LIBRENMS_DB
        LIBRENMS_DB=${LIBRENMS_DB:-librenms}
        if validate_input "$LIBRENMS_DB" "Nome do banco de dados"; then
            break
        fi
    done

    # Usuário do banco de dados
    while true; do
        read -p "Usuário do banco de dados LibreNMS [librenms]: " LIBRENMS_DB_USER
        LIBRENMS_DB_USER=${LIBRENMS_DB_USER:-librenms}
        if validate_input "$LIBRENMS_DB_USER" "Usuário do banco de dados"; then
            break
        fi
    done

    # Senha do banco de dados
    while true; do
        read -s -p "Senha do banco de dados LibreNMS: " LIBRENMS_DB_PASSWORD
        echo
        if validate_password "$LIBRENMS_DB_PASSWORD"; then
            read -s -p "Confirme a senha: " LIBRENMS_DB_PASSWORD_CONFIRM
            echo
            if [ "$LIBRENMS_DB_PASSWORD" = "$LIBRENMS_DB_PASSWORD_CONFIRM" ]; then
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

    # Comunidade SNMP
    while true; do
        read -p "Comunidade SNMP [librenms]: " SNMP_COMMUNITY
        SNMP_COMMUNITY=${SNMP_COMMUNITY:-librenms}
        if validate_input "$SNMP_COMMUNITY" "Comunidade SNMP"; then
            break
        fi
    done

    # Timezone
    while true; do
        read -p "Timezone [America/Sao_Paulo]: " TIMEZONE
        TIMEZONE=${TIMEZONE:-America/Sao_Paulo}
        if validate_input "$TIMEZONE" "Timezone"; then
            break
        fi
    done

    # Senha do administrador
    while true; do
        read -s -p "Senha do administrador LibreNMS: " ADMIN_PASSWORD
        echo
        if validate_password "$ADMIN_PASSWORD"; then
            read -s -p "Confirme a senha: " ADMIN_PASSWORD_CONFIRM
            echo
            if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
                break
            else
                print_error "As senhas não coincidem!"
            fi
        fi
    done
fi

echo
print_info "Configurações coletadas:"
echo "  • Banco de dados: $LIBRENMS_DB"
echo "  • Usuário: $LIBRENMS_DB_USER"
echo "  • Servidor: $SERVER_NAME"
echo "  • Porta: $SERVER_PORT"
echo "  • Comunidade SNMP: $SNMP_COMMUNITY"
echo "  • Timezone: $TIMEZONE"
echo "  • Usuário admin: admin"
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
if [[ "$OS_NAME" != "ubuntu" && "$OS_NAME" != "debian" ]]; then
    print_error "Sistema não suportado: $OS_NAME"
    print_info "Este script suporta apenas Ubuntu e Debian."
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
# Instalar dependências
# -----------------------------
print_info "Instalando dependências do LibreNMS..."
if sudo apt install -q -y \
    lsb-release ca-certificates wget acl curl fping git graphviz imagemagick \
    mariadb-client mariadb-server mtr-tiny nginx-full nmap php-cli php-curl \
    php-fpm php-gd php-gmp php-mbstring php-mysql php-snmp php-xml php-zip \
    python3-command-runner python3-dotenv python3-pymysql python3-redis \
    python3-setuptools python3-systemd python3-pip python3-psutil rrdtool snmp snmpd \
    unzip whois crudini; then
    print_success "Dependências instaladas com sucesso"
else
    print_error "Falha ao instalar dependências"
    exit 1
fi

# -----------------------------
# Criar usuário LibreNMS
# -----------------------------
print_info "Criando usuário LibreNMS..."
if sudo useradd librenms -d /opt/librenms -M -r -s "$(which bash)" 2>/dev/null || true; then
    print_success "Usuário LibreNMS criado/verificado com sucesso"
else
    print_warning "Usuário LibreNMS pode já existir"
fi

# -----------------------------
# Baixar e configurar LibreNMS
# -----------------------------
print_info "Baixando LibreNMS..."
cd /opt
if sudo git clone https://github.com/librenms/librenms.git; then
    print_success "LibreNMS baixado com sucesso"
else
    print_error "Falha ao baixar LibreNMS"
    exit 1
fi

print_info "Configurando permissões do LibreNMS..."
if sudo chown -R librenms:librenms /opt/librenms && \
   sudo chmod 771 /opt/librenms && \
   sudo setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/ && \
   sudo setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/; then
    print_success "Permissões configuradas com sucesso"
else
    print_error "Falha ao configurar permissões"
    exit 1
fi

print_info "Instalando dependências PHP do LibreNMS..."
if sudo su - librenms -c "cd /opt/librenms && ./scripts/composer_wrapper.php install --no-dev" >/dev/null 2>&1; then
    print_success "Dependências PHP instaladas com sucesso"
else
    print_error "Falha ao instalar dependências PHP"
    exit 1
fi

# -----------------------------
# Configurar PHP
# -----------------------------
print_info "Configurando PHP..."
if sudo sed -i "s|^;*date.timezone =.*|date.timezone = ${TIMEZONE}|" /etc/php/8.4/fpm/php.ini && \
   sudo sed -i "s|^;*date.timezone =.*|date.timezone = ${TIMEZONE}|" /etc/php/8.4/cli/php.ini; then
    print_success "PHP configurado com sucesso"
else
    print_error "Falha ao configurar PHP"
    exit 1
fi

# -----------------------------
# Configurar MariaDB
# -----------------------------
print_info "Configurando MariaDB..."
if crudini --set /etc/mysql/my.cnf mysqld innodb_file_per_table 1 >/dev/null 2>&1 && \
   crudini --set /etc/mysql/my.cnf mysqld lower_case_table_names 0 >/dev/null 2>&1; then
    print_success "Configurações do MariaDB aplicadas com sucesso"
else
    print_error "Falha ao aplicar configurações do MariaDB"
    exit 1
fi

print_info "Configurando segurança do MariaDB..."
if sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${LIBRENMS_DB_PASSWORD}';
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

# Criar banco de dados e usuário LibreNMS
print_info "Criando banco de dados e usuário LibreNMS..."
if sudo mysql -u root -p"${LIBRENMS_DB_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${LIBRENMS_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${LIBRENMS_DB_USER}'@'localhost' IDENTIFIED BY '${LIBRENMS_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${LIBRENMS_DB}\`.* TO '${LIBRENMS_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
then
    print_success "Banco de dados e usuário criados com sucesso"
else
    print_error "Falha ao criar banco de dados e usuário"
    exit 1
fi

# -----------------------------
# Configurar PHP-FPM
# -----------------------------
print_info "Configurando PHP-FPM para LibreNMS..."
if sudo cp /etc/php/8.4/fpm/pool.d/www.conf /etc/php/8.4/fpm/pool.d/librenms.conf && \
   sudo sed -i 's/^\[www\]/[librenms]/' /etc/php/8.4/fpm/pool.d/librenms.conf && \
   sudo sed -i 's/^user = .*/user = librenms/' /etc/php/8.4/fpm/pool.d/librenms.conf && \
   sudo sed -i 's/^group = .*/group = librenms/' /etc/php/8.4/fpm/pool.d/librenms.conf && \
   sudo sed -i 's|^listen = .*|listen = /run/php-fpm-librenms.sock|' /etc/php/8.4/fpm/pool.d/librenms.conf && \
   sudo rm /etc/php/8.4/fpm/pool.d/www.conf; then
    print_success "PHP-FPM configurado com sucesso"
else
    print_error "Falha ao configurar PHP-FPM"
    exit 1
fi

# Detectar o nome exato do serviço PHP-FPM
PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=active | grep -o 'php[0-9.]*-fpm' | head -1)
if [[ -z "$PHP_FPM_SERVICE" ]]; then
    PHP_FPM_SERVICE=$(ls /lib/systemd/system/php*-fpm.service 2>/dev/null | head -1 | xargs basename | sed 's/\.service$//')
fi

if [[ -n "$PHP_FPM_SERVICE" ]]; then
    print_info "Reiniciando $PHP_FPM_SERVICE..."
    if sudo systemctl restart "$PHP_FPM_SERVICE"; then
        print_success "PHP-FPM reiniciado com sucesso"
    else
        print_error "Falha ao reiniciar PHP-FPM"
        exit 1
    fi
else
    print_warning "Serviço PHP-FPM não detectado"
fi

# -----------------------------
# Configurar Nginx
# -----------------------------
print_info "Configurando Nginx..."
if sudo tee /etc/nginx/sites-enabled/librenms.vhost > /dev/null <<EOF
server {
    listen      $SERVER_PORT;
    server_name $SERVER_NAME;
    root        /opt/librenms/html;
    index       index.php;

    charset utf-8;

    gzip on;
    gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ [^/]\.php(/|$) {
        fastcgi_pass unix:/run/php-fpm-librenms.sock;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        include fastcgi.conf;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
then
    print_success "Nginx configurado com sucesso"
else
    print_error "Falha ao configurar Nginx"
    exit 1
fi

# -----------------------------
# Configurar LibreNMS
# -----------------------------
print_info "Configurando LibreNMS..."
if sudo ln -s /opt/librenms/lnms /usr/bin/lnms && \
   sudo cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/; then
    print_success "Comandos LibreNMS configurados com sucesso"
else
    print_error "Falha ao configurar comandos LibreNMS"
    exit 1
fi

print_info "Criando arquivo de configuração do LibreNMS..."
if sudo tee /opt/librenms/.env > /dev/null <<EOF
APP_NAME=LibreNMS
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://${SERVER_NAME}

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=${LIBRENMS_DB}
DB_USERNAME=${LIBRENMS_DB_USER}
DB_PASSWORD=${LIBRENMS_DB_PASSWORD}

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

MEMCACHED_HOST=127.0.0.1

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="\${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=
AWS_USE_PATH_STYLE_ENDPOINT=false

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_HOST=
PUSHER_PORT=443
PUSHER_SCHEME=https
PUSHER_APP_CLUSTER=mt1

VITE_PUSHER_APP_KEY="\${PUSHER_APP_KEY}"
VITE_PUSHER_HOST="\${PUSHER_HOST}"
VITE_PUSHER_PORT="\${PUSHER_PORT}"
VITE_PUSHER_SCHEME="\${PUSHER_SCHEME}"
VITE_PUSHER_APP_CLUSTER="\${PUSHER_APP_CLUSTER}"
EOF
then
    print_success "Arquivo de configuração criado com sucesso"
else
    print_error "Falha ao criar arquivo de configuração"
    exit 1
fi

print_info "Configurando permissões do arquivo .env..."
if sudo chown librenms:librenms /opt/librenms/.env && \
   sudo chmod 600 /opt/librenms/.env; then
    print_success "Permissões do arquivo .env configuradas com sucesso"
else
    print_error "Falha ao configurar permissões do arquivo .env"
    exit 1
fi

print_info "Gerando chave de aplicação..."
if sudo su - librenms -c "cd /opt/librenms && ./lnms key:generate" >/dev/null 2>&1; then
    print_success "Chave de aplicação gerada com sucesso"
else
    print_error "Falha ao gerar chave de aplicação"
    exit 1
fi

print_info "Executando migrações do banco de dados..."
if sudo su - librenms -c "cd /opt/librenms && ./lnms migrate --force" >/dev/null 2>&1; then
    print_success "Migrações executadas com sucesso"
else
    print_error "Falha ao executar migrações"
    exit 1
fi

print_info "Executando seeders do banco de dados..."
if sudo su - librenms -c "cd /opt/librenms && ./lnms db:seed --force" >/dev/null 2>&1; then
    print_success "Seeders executados com sucesso"
else
    print_error "Falha ao executar seeders"
    exit 1
fi

print_info "Configurando base_url..."
if sudo su - librenms -c "cd /opt/librenms && ./lnms config:set base_url http://${SERVER_NAME}" >/dev/null 2>&1; then
    print_success "base_url configurado com sucesso"
else
    print_error "Falha ao configurar base_url"
    exit 1
fi

print_info "Criando usuário administrador..."
if sudo su - librenms -c "cd /opt/librenms && ./lnms user:add admin -p '${ADMIN_PASSWORD}' -r admin" >/dev/null 2>&1; then
    print_success "Usuário administrador criado com sucesso"
else
    print_error "Falha ao criar usuário administrador"
    exit 1
fi

# -----------------------------
# Configurar SNMP
# -----------------------------
print_info "Configurando SNMP..."
if sudo cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf && \
   sudo sed -i "s/RANDOMSTRINGGOESHERE/${SNMP_COMMUNITY}/g" /etc/snmp/snmpd.conf && \
   sudo curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro && \
   sudo chmod +x /usr/bin/distro; then
    print_success "SNMP configurado com sucesso"
else
    print_error "Falha ao configurar SNMP"
    exit 1
fi

# -----------------------------
# Configurar serviços e cron
# -----------------------------
print_info "Configurando serviços e cron..."
if sudo cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms && \
   sudo cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/ && \
   sudo cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms; then
    print_success "Serviços e cron configurados com sucesso"
else
    print_error "Falha ao configurar serviços e cron"
    exit 1
fi

# -----------------------------
# Iniciar e habilitar serviços
# -----------------------------
print_info "Iniciando e habilitando serviços..."
SERVICES="nginx snmpd librenms-scheduler.timer"
if [[ -n "$PHP_FPM_SERVICE" ]]; then
    SERVICES="$SERVICES $PHP_FPM_SERVICE"
fi

if sudo systemctl restart $SERVICES && \
   sudo systemctl enable $SERVICES; then
    print_success "Serviços iniciados e habilitados com sucesso"
else
    print_error "Falha ao iniciar/habilitar serviços"
    exit 1
fi

# -----------------------------
# Verificar status dos serviços
# -----------------------------
print_info "Verificando status dos serviços..."
if systemctl is-active --quiet nginx && \
   systemctl is-active --quiet snmpd; then
    if [[ -n "$PHP_FPM_SERVICE" ]] && systemctl is-active --quiet "$PHP_FPM_SERVICE"; then
        print_success "Todos os serviços estão rodando"
    elif [[ -n "$PHP_FPM_SERVICE" ]]; then
        print_warning "PHP-FPM pode não estar rodando corretamente"
    else
        print_success "Serviços principais estão rodando"
    fi
else
    print_warning "Alguns serviços podem não estar rodando corretamente"
fi

echo
print_success "Instalação concluída com sucesso!"
echo
print_info "Informações de acesso:"
echo "  • URL: http://${SERVER_NAME}:${SERVER_PORT}"
echo "  • Comunidade SNMP: $SNMP_COMMUNITY"
echo
print_success "LibreNMS está pronto para uso!"
echo "  • Banco de dados configurado"
echo "  • Migrações executadas"
echo "  • Seeders executados"
echo "  • Usuário administrador criado"
echo
print_info "Credenciais de acesso:"
echo "  • Usuário: admin"
echo "  • Senha: [a senha que você definiu]"
echo
print_info "Para verificar o status dos serviços, execute:"
echo "  sudo systemctl status nginx snmpd $PHP_FPM_SERVICE"