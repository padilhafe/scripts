#!/bin/bash
set -euo pipefail

# Configuráveis
ROLE_NAME="TerraformProv"
USER_NAME="terraform-prov@pve"
TOKEN_NAME="terraform-token"

# Privileges para Proxmox v9 (mais granular)
PRIVS_V9="Datastore.AllocateSpace Datastore.Audit Datastore.AllocateTemplate Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# Privileges para Proxmox v8 (formato legado)
PRIVS_V8="VM.Clone, VM.Config.Disk, Sys.Modify, Sys.Audit, VM.Allocate, VM.Migrate, VM.Config.Network, Datastore.AllocateSpace, Pool.Allocate, VM.PowerMgmt, VM.Monitor, VM.Config.CDROM, Datastore.AllocateTemplate, VM.Config.Memory, VM.Audit, VM.Config.CPU, SDN.Use, VM.Config.Cloudinit, Sys.Console, VM.Config.Options, Datastore.Audit, VM.Config.HWType"

# Função de log
info() { printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
err()  { printf "\e[1;31m[ERROR]\e[0m %s\n" "$*" >&2; }

# Verifica dependências
for cmd in pveversion pveum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Comando '$cmd' não encontrado. Rode este script no host Proxmox como root."
    exit 1
  fi
done

# Descobre a versão major do Proxmox (extrai o primeiro número do pve-manager ou da saída pveversion)
get_pve_major() {
  # tenta extrair "pve-manager/x.y-z" da saída de pveversion -v, ou fallback para pveversion simples
  if pveversion -v >/dev/null 2>&1; then
    # pega a linha que contenha pve-manager e extrai primeiro número
    local line
    line=$(pveversion -v | awk -F'/' '/pve-manager/{print $2; exit}' || true)
    if [[ -n "$line" ]]; then
      # line ex: "9.0-1" -> extrai 9
      echo "$line" | sed -E 's/^([0-9]+).*/\1/'
      return
    fi
  fi

  # fallback: pveversion prints algo como "pve-manager/9.0-1"
  local pv
  pv=$(pveversion 2>/dev/null || true)
  if [[ -n "$pv" ]]; then
    echo "$pv" | sed -E 's/[^0-9]*([0-9]+).*/\1/'
    return
  fi

  # se nada der certo, assume 8 (seguro)
  echo "8"
}

PVE_MAJOR=$(get_pve_major)
info "Detected Proxmox major version: ${PVE_MAJOR}"

# Seleciona privilégios conforme versão
if [[ "${PVE_MAJOR}" -ge 9 ]]; then
  PRIVS="${PRIVS_V9}"
  info "Usando lista de privilégios para Proxmox v9+"
else
  PRIVS="${PRIVS_V8}"
  info "Usando lista de privilégios para Proxmox v8/legado"
fi

# 1 - Criar Role (se já existir, ignora)
if pveum role list | awk '{print $1}' | grep -qx "${ROLE_NAME}"; then
  warn "Role '${ROLE_NAME}' já existe — pulando criação."
else
  info "Criando role '${ROLE_NAME}'..."
  # Para evitar problemas com espaços vs vírgulas, usamos a forma correta conforme versão:
  if [[ "${PVE_MAJOR}" -ge 9 ]]; then
    pveum role add "${ROLE_NAME}" -privs "${PRIVS}"
  else
    # pveum aceita a string com vírgulas para v8
    pveum role add "${ROLE_NAME}" -privs "${PRIVS}"
  fi
  info "Role criada."
fi

# 2 - Criar usuário sem senha (se já existir, ignora)
if pveum user list | awk '{print $1}' | grep -qx "${USER_NAME}"; then
  warn "Usuário '${USER_NAME}' já existe — pulando criação."
else
  info "Criando usuário '${USER_NAME}' (sem senha)..."
  # --keys '' cria sem chave pública; se quiser, adicione uma chave pública SSH aqui
  pveum user add "${USER_NAME}" --keys '' || { err "Falha ao criar usuário"; exit 1; }
  info "Usuário criado."
fi

# 3 - Associar a Role ao Usuário na ACL do / (root) - se já existir, ignora
if pveum acl list / | grep -q "${USER_NAME}"; then
  warn "ACL já contém entradas para ${USER_NAME} em / — pulando aclmod."
else
  info "Associação ACL: concedendo role '${ROLE_NAME}' ao usuário '${USER_NAME}' na rota '/'."
  pveum aclmod / -user "${USER_NAME}" -role "${ROLE_NAME}" || { err "Falha ao modificar ACL"; exit 1; }
  info "ACL aplicada."
fi

# 4 - Criar API Token
info "Criando API token '${TOKEN_NAME}' para ${USER_NAME}..."
# A saída do pveum user token add normalmente contém o token (a parte secreta) apenas no momento da criação.
# Capturamos a saída inteira e tentamos extrair a linha que contenha "token:" ou o valor apresentado.
API_OUTPUT=$(pveum user token add "${USER_NAME}" "${TOKEN_NAME}" --privsep 0 2>&1) || { err "Falha ao criar token: $API_OUTPUT"; exit 1; }

# Tenta extrair a parte "token" da saída (varia entre versões)
# Exemplos possíveis:
#   token: <secret>
#   or a single-line with the secret
API_TOKEN=""
# tenta padrão "token: <secret>"
API_TOKEN=$(echo "$API_OUTPUT" | awk -F': ' '/[Tt]oken:/{print $2; exit}' || true)
if [[ -z "${API_TOKEN}" ]]; then
  # pega última linha não vazia como fallback
  API_TOKEN=$(echo "$API_OUTPUT" | sed -n '/\S/,$p' | tail -n1 || true)
fi

if [[ -z "${API_TOKEN}" ]]; then
  warn "Não foi possível extrair automaticamente o token secreto da saída. Veja a saída completa abaixo e anote manualmente:"
  echo "---- saída de pveum user token add ----"
  echo "$API_OUTPUT"
  echo "--------------------------------------"
  err "Token não encontrado na saída. Anote-o manualmente agora."
  exit 1
fi

# 5 - Exibir instruções para uso
echo
info "Seu API Token foi gerado com sucesso! Anote imediatamente — não poderá ser recuperado depois."
echo
echo "Usuário (ID): ${USER_NAME}!${TOKEN_NAME}"
echo "Token secreto: ${API_TOKEN}"
echo
info "Exemplo de uso com pvesh (ou exportar variáveis):"
echo "  export PVE_USER='${USER_NAME}!${TOKEN_NAME}'"
echo "  export PVE_TOKEN='${API_TOKEN}'"
echo
info "Observações finais:"
echo " - Guarde o token em local seguro (cofre/secret manager)."
echo " - Se preferir, crie o token com escopo/expire conforme sua política de segurança."
