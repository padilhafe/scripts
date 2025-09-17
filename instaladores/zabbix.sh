#!/bin/bash
# Script de Instalação do Zabbix 7 no Ubuntu/Debian - Instalação Interativa

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
    echo -e "${BLUE}  Instalação do Zabbix 7${NC}"
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
    
    if [[ -n "${ZABBIX_DB:-}" ]]; then
        existing_vars+=("ZABBIX_DB=$ZABBIX_DB")
    fi
    if [[ -n "${ZABBIX_DB_USER:-}" ]]; then
        existing_vars+=("ZABBIX_DB_USER=$ZABBIX_DB_USER")
    fi
    if [[ -n "${ZABBIX_DB_PASSWORD:-}" ]]; then
        existing_vars+=("ZABBIX_DB_PASSWORD=***")
    fi
    if [[ -n "${SERVER_NAME:-}" ]]; then
        existing_vars+=("SERVER_NAME=$SERVER_NAME")
    fi
    if [[ -n "${SERVER_PORT:-}" ]]; then
        existing_vars+=("SERVER_PORT=$SERVER_PORT")
    fi
    if [[ -n "${TIMEZONE:-}" ]]; then
        existing_vars+=("TIMEZONE=$TIMEZONE")
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

echo -e "${YELLOW}Este script irá instalar o Zabbix 7 no seu sistema.${NC}"

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
        ZABBIX_DB=${ZABBIX_DB:-zabbix}
        ZABBIX_DB_USER=${ZABBIX_DB_USER:-zabbix}
        SERVER_NAME=${SERVER_NAME:-$(get_network_ip)}
        SERVER_PORT=${SERVER_PORT:-80}
        TIMEZONE=${TIMEZONE:-America/Sao_Paulo}
        
        # Verificar se a senha está definida
        if [[ -z "${ZABBIX_DB_PASSWORD:-}" ]]; then
            print_warning "Senha do banco de dados não encontrada nas variáveis de ambiente."
            while true; do
                read -s -p "Senha do banco de dados Zabbix: " ZABBIX_DB_PASSWORD
                echo
                if validate_password "$ZABBIX_DB_PASSWORD"; then
                    read -s -p "Confirme a senha: " ZABBIX_DB_PASSWORD_CONFIRM
                    echo
                    if [ "$ZABBIX_DB_PASSWORD" = "$ZABBIX_DB_PASSWORD_CONFIRM" ]; then
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
if [[ -z "${ZABBIX_DB:-}" ]] || [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Por favor, forneça as seguintes informações:${NC}"
    echo

    # Nome do banco de dados
    while true; do
        read -p "Nome do banco de dados Zabbix [zabbix]: " ZABBIX_DB
        ZABBIX_DB=${ZABBIX_DB:-zabbix}
        if validate_input "$ZABBIX_DB" "Nome do banco de dados"; then
            break
        fi
    done

    # Usuário do banco de dados
    while true; do
        read -p "Usuário do banco de dados Zabbix [zabbix]: " ZABBIX_DB_USER
        ZABBIX_DB_USER=${ZABBIX_DB_USER:-zabbix}
        if validate_input "$ZABBIX_DB_USER" "Usuário do banco de dados"; then
            break
        fi
    done

    # Senha do banco de dados
    while true; do
        read -s -p "Senha do banco de dados Zabbix: " ZABBIX_DB_PASSWORD
        echo
        if validate_password "$ZABBIX_DB_PASSWORD"; then
            read -s -p "Confirme a senha: " ZABBIX_DB_PASSWORD_CONFIRM
            echo
            if [ "$ZABBIX_DB_PASSWORD" = "$ZABBIX_DB_PASSWORD_CONFIRM" ]; then
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

    # Timezone
    while true; do
        read -p "Timezone [America/Sao_Paulo]: " TIMEZONE
        TIMEZONE=${TIMEZONE:-America/Sao_Paulo}
        if validate_input "$TIMEZONE" "Timezone"; then
            break
        fi
    done
fi

echo
print_info "Configurações coletadas:"
echo "  • Banco de dados: $ZABBIX_DB"
echo "  • Usuário: $ZABBIX_DB_USER"
echo "  • Servidor: $SERVER_NAME"
echo "  • Porta: $SERVER_PORT"
echo "  • Timezone: $TIMEZONE"
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

# Formata versão para o pacote do Zabbix
if [ "$OS_NAME" = "ubuntu" ]; then
    PACKAGE_VERSION="$OS_VERSION"
elif [ "$OS_NAME" = "debian" ]; then
    PACKAGE_VERSION="${OS_VERSION%%.*}"
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
# Instalar MariaDB
# -----------------------------
print_info "Instalando MariaDB..."
if sudo apt install -q -y mariadb-server mariadb-client; then
    print_success "MariaDB instalado com sucesso"
else
    print_error "Falha ao instalar MariaDB"
    exit 1
fi

# -----------------------------
# Configurar MariaDB
# -----------------------------
print_info "Configurando MariaDB..."
if sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
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

# Criar banco de dados e usuário Zabbix
print_info "Criando banco de dados e usuário Zabbix..."
if sudo mysql -u root -p"${ZABBIX_DB_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${ZABBIX_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${ZABBIX_DB}\`.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
then
    print_success "Banco de dados e usuário criados com sucesso"
else
    print_error "Falha ao criar banco de dados e usuário"
    exit 1
fi

# -----------------------------
# Instalar repositório do Zabbix
# -----------------------------
print_info "Configurando repositório do Zabbix..."
ZABBIX_BASE_URL="https://repo.zabbix.com/zabbix/7.0/${OS_NAME}/pool/main/z/zabbix-release"
PACKAGE_NAME="zabbix-release_latest+${OS_NAME}${PACKAGE_VERSION}_all.deb"
DOWNLOAD_URL="${ZABBIX_BASE_URL}/${PACKAGE_NAME}"

print_info "Baixando Zabbix release para $OS_NAME $OS_VERSION..."
if wget --quiet --show-progress "$DOWNLOAD_URL" -O "$PACKAGE_NAME"; then
    print_success "Pacote baixado com sucesso"
else
    print_error "Falha ao baixar o pacote do Zabbix"
    exit 1
fi

if sudo dpkg -i "$PACKAGE_NAME" >/dev/null 2>&1 && rm "$PACKAGE_NAME" && sudo apt update -q -y; then
    print_success "Repositório do Zabbix configurado com sucesso"
else
    print_error "Falha ao configurar repositório do Zabbix"
    exit 1
fi

# -----------------------------
# Instalar pacotes do Zabbix
# -----------------------------
print_info "Instalando pacotes do Zabbix..."
if sudo apt install -q -y \
    zabbix-server-mysql \
    zabbix-frontend-php \
    zabbix-nginx-conf \
    zabbix-agent \
    zabbix-sql-scripts; then
    print_success "Pacotes do Zabbix instalados com sucesso"
else
    print_error "Falha ao instalar pacotes do Zabbix"
    exit 1
fi

# -----------------------------
# Configurar Zabbix server e Nginx
# -----------------------------
print_info "Configurando Zabbix server e Nginx..."
if sudo sed -i "s/^#\s*\(DBPassword=\).*/\1${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf && \
   sudo sed -i -E "s@#(\s*listen\s+)8080;@\1${SERVER_PORT};@" /etc/zabbix/nginx.conf && \
   sudo sed -i -E "s@#(\s*server_name\s+)example.com;@\1${SERVER_NAME};@" /etc/zabbix/nginx.conf && \
   echo "php_value[date.timezone] = ${TIMEZONE}" | sudo tee -a /etc/zabbix/php-fpm.conf; then
    print_success "Configurações aplicadas com sucesso"
else
    print_error "Falha ao aplicar configurações"
    exit 1
fi

# -----------------------------
# Popular banco de dados Zabbix
# -----------------------------
print_info "Populando banco de dados Zabbix..."
if zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
   mysql --default-character-set=utf8mb4 -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASSWORD}" "${ZABBIX_DB}"; then
    print_success "Banco de dados populado com sucesso"
else
    print_error "Falha ao popular banco de dados"
    exit 1
fi

# -----------------------------
# Reiniciar e habilitar serviços
# -----------------------------
print_info "Reiniciando e habilitando serviços..."

# Detectar o nome exato do serviço PHP-FPM
PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=active | grep -o 'php[0-9.]*-fpm' | head -1)
if [[ -z "$PHP_FPM_SERVICE" ]]; then
    # Fallback: tentar detectar por arquivo de serviço
    PHP_FPM_SERVICE=$(ls /lib/systemd/system/php*-fpm.service 2>/dev/null | head -1 | xargs basename | sed 's/\.service$//')
fi

if [[ -n "$PHP_FPM_SERVICE" ]]; then
    print_info "Serviço PHP-FPM detectado: $PHP_FPM_SERVICE"
    SERVICES="zabbix-server zabbix-agent nginx $PHP_FPM_SERVICE"
else
    print_warning "Serviço PHP-FPM não detectado, continuando sem ele"
    SERVICES="zabbix-server zabbix-agent nginx"
fi

if sudo systemctl restart $SERVICES && \
   sudo systemctl enable $SERVICES; then
    print_success "Serviços configurados e iniciados com sucesso"
else
    print_error "Falha ao configurar serviços"
    exit 1
fi

# -----------------------------
# Verificar status dos serviços
# -----------------------------
print_info "Verificando status dos serviços..."
if systemctl is-active --quiet zabbix-server && \
   systemctl is-active --quiet zabbix-agent && \
   systemctl is-active --quiet nginx; then
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
echo "  • Usuário padrão: Admin"
echo "  • Senha padrão: zabbix"
echo
print_warning "IMPORTANTE: Altere a senha padrão após o primeiro login!"
echo
print_info "Para verificar o status dos serviços, execute:"
echo "  sudo systemctl status zabbix-server zabbix-agent nginx"
