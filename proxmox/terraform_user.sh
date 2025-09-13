#!/bin/bash
set -euo pipefail

# Configuráveis
ROLE_NAME="TerraformProv"
USER_NAME="terraform-prov@pve"
TOKEN_NAME="terraform-token"

PRIVS_V9="Datastore.AllocateSpace Datastore.Audit Datastore.AllocateTemplate Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"
PRIVS_V8="Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"

info() { printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
err()  { printf "\e[1;31m[ERROR]\e[0m %s\n" "$*" >&2; }

# Verifica dependências mínimas
for cmd in pveversion pveum dpkg-query; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Comando '$cmd' não encontrado. Pode não ser crítico, mas a detecção de versão pode falhar."
  fi
done

# Detecta major version do Proxmox (métodos em cascata)
get_pve_major() {
  # 1) tentar dpkg-query no pacote pve-manager (mais confiável em muitos setups)
  if dpkg-query -W -f='${Version}' pve-manager >/dev/null 2>&1; then
    ver=$(dpkg-query -W -f='${Version}' pve-manager 2>/dev/null || true)
    if [[ -n "$ver" ]]; then
      echo "$ver" | sed -E 's/^([0-9]+).*/\1/'
      return
    fi
  fi

  # 2) tentar pveversion -v parse
  if command -v pveversion >/dev/null 2>&1; then
    pv=$(pveversion -v 2>/dev/null | awk -F'/' '/pve-manager/{print $2; exit}' || true)
    if [[ -n "$pv" ]]; then
      echo "$pv" | sed -E 's/^([0-9]+).*/\1/'
      return
    fi
  fi

  # fallback seguro
  echo "8"
}

PVE_MAJOR=$(get_pve_major)
info "Detected Proxmox major version: ${PVE_MAJOR}"

if [[ "${PVE_MAJOR}" -ge 9 ]]; then
  PRIVS="${PRIVS_V9}"
  info "Usando lista de privilégios para Proxmox v9+"
else
  PRIVS="${PRIVS_V8}"
  info "Usando lista de privilégios para Proxmox v8/legado"
fi

# 1 - Criar role (se não existir)
if pveum role list 2>/dev/null | awk '{print $1}' | grep -qx "${ROLE_NAME}"; then
  warn "Role '${ROLE_NAME}' já existe — pulando criação."
else
  info "Criando role '${ROLE_NAME}'..."
  pveum role add "${ROLE_NAME}" -privs "${PRIVS}"
  info "Role criada."
fi

# 2 - Criar usuário sem senha (se não existir)
if pveum user list 2>/dev/null | awk '{print $1}' | grep -qx "${USER_NAME}"; then
  warn "Usuário '${USER_NAME}' já existe — pulando criação."
else
  info "Criando usuário '${USER_NAME}' (sem senha)..."
  pveum user add "${USER_NAME}" --keys '' || { err "Falha ao criar usuário"; exit 1; }
  info "Usuário criado."
fi

# 3 - Aplicar ACL (sem checar via pveum acl list para evitar erro de 'too many args')
info "Associando role '${ROLE_NAME}' ao usuário '${USER_NAME}' na rota '/'."
if ! pveum aclmod / -user "${USER_NAME}" -role "${ROLE_NAME}" 2>/tmp/pve_aclmod_out.$$; then
  warn "pveum aclmod retornou erro (veja /tmp/pve_aclmod_out.$$). Continuando..."
  sed -n '1,200p' /tmp/pve_aclmod_out.$$ || true
else
  info "ACL aplicada."
fi
rm -f /tmp/pve_aclmod_out.$$ || true

# 4 - Criar API token e extrair o segredo de forma robusta
info "Criando API token '${TOKEN_NAME}' para ${USER_NAME}..."
API_OUTPUT=$(pveum user token add "${USER_NAME}" "${TOKEN_NAME}" --privsep 0 2>&1) || { err "Falha ao criar token. Saída:"; echo "$API_OUTPUT"; exit 1; }

# Limpa caracteres de borda da tabela (box-drawing) e espaços em excesso
CLEAN=$(printf "%s\n" "$API_OUTPUT" | tr -d '┌┐└┘─│' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Tenta encontrar linha que comece com "token"
API_TOKEN_LINE=$(printf "%s\n" "$CLEAN" | grep -i -m1 -E '^[[:space:]]*token([[:space:]]|:)' || true)

if [[ -n "$API_TOKEN_LINE" ]]; then
  # extrai depois de ":" se houver, senão pega último campo
  API_TOKEN=$(printf "%s\n" "$API_TOKEN_LINE" | awk -F': ' '{ if (NF>=2) {print $2} else { $1=""; sub("^ +",""); print } }' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
else
  # fallback: pega primeira linha que contenha 'token' MAS que NÃO seja tokenid
  API_TOKEN_LINE=$(printf "%s\n" "$CLEAN" | grep -i -m1 'token' | grep -iv 'tokenid' || true)
  if [[ -n "$API_TOKEN_LINE" ]]; then
    API_TOKEN=$(printf "%s\n" "$API_TOKEN_LINE" | awk -F': ' '{ if (NF>=2) print $2; else print $NF }' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  else
    API_TOKEN=""
  fi
fi

# limpeza final: remover caracteres não imprimíveis e trim
API_TOKEN=$(printf "%s" "$API_TOKEN" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ -z "${API_TOKEN}" ]]; then
  warn "Não consegui extrair automaticamente o token secreto. Aqui está a saída completa (copie manualmente a linha 'token' ou 'token:'):"
  echo "---- saída completa do pveum user token add ----"
  echo "$API_OUTPUT"
  echo "------------------------------------------------"
  exit 1
fi

echo
info "Token gerado com sucesso. ANOTE IMEDIATAMENTE — não poderá ser recuperado depois."
echo "Usuário (ID): ${USER_NAME}!${TOKEN_NAME}"
echo "Token secreto: ${API_TOKEN}"
echo
info "Exemplo de uso:"
echo "  export PVE_USER='${USER_NAME}!${TOKEN_NAME}'"
echo "  export PVE_TOKEN='${API_TOKEN}'"
echo
info "Guarde o token em um cofre/secret manager e considere políticas de expiração/escopo se necessário."
