#!/bin/bash

# Configurações fixas
IMAGES_PATH="/var/lib/vz/images"
VM_RESOURCE_POOL="cloud_init"
QEMU_CPU_MODEL="x86-64-v2-AES"
VM_CPU_SOCKETS=1
VM_CPU_CORES=1
VM_MEMORY=1024
VM_BRIDGE="vmbr0"
VM_TAG="30"
VM_MTU=1
CLOUD_INIT_IP="dhcp"
CLOUD_INIT_NAMESERVER="8.8.8.8"
CLOUD_INIT_USER="ciuser"
CLOUD_INIT_PASSWORD="cipass"
NODE_ID=0

# Lista de imagens: "nome_lógico;ID_TEMPLATE;URL"
IMAGES_LIST=(
  "debian-12;02;https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  "debian-13;03;https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  "ubuntu-2204;11;https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  "ubuntu-2404;12;https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
)

# Função para criar template
create_template() {
  local VM_NAME=$1
  local ID_TEMPLATE=$2
  local IMAGE_URL=$3
  local TEMPLATE_ID="9${NODE_ID}${ID_TEMPLATE}"
  local IMAGE_FILE="${IMAGES_PATH}/${VM_NAME}.img"

  echo "--------------------------------------------"
  echo "Preparando template ${VM_NAME} (ID ${TEMPLATE_ID})"
  echo "--------------------------------------------"

  # Ir para o diretório de imagens
  cd ${IMAGES_PATH} || exit 1

  # Download da imagem se não existir
  if [ ! -f "${IMAGE_FILE}" ]; then
    echo "Baixando imagem ${VM_NAME}..."
    wget -O "${IMAGE_FILE}" "${IMAGE_URL}"
  else
    echo "Imagem ${VM_NAME} já existe. Pulando download."
  fi

  # Montando o parâmetro de rede condicionalmente
  if [ "${VM_TAG}" -eq 0 ]; then
      NET_OPTS="virtio,bridge=${VM_BRIDGE},mtu=${VM_MTU}"
  else
      NET_OPTS="virtio,bridge=${VM_BRIDGE},mtu=${VM_MTU},tag=${VM_TAG}"
  fi

  # Criando a VM
  qm create ${TEMPLATE_ID} \
    --name ${VM_NAME} \
    --cpu ${QEMU_CPU_MODEL} \
    --sockets ${VM_CPU_SOCKETS} \
    --cores ${VM_CPU_CORES} \
    --memory ${VM_MEMORY} \
    --net0 ${NET_OPTS} \
    --ostype l26 \
    --agent 1 \
    --pool ${VM_RESOURCE_POOL} \
    --scsihw virtio-scsi-single

  # Modificando configurações da VM
  qm set ${TEMPLATE_ID} \
      --scsi0 local-lvm:0,import-from=${IMAGE_FILE} \
      --ide2 local-lvm:cloudinit \
      --boot order=scsi0 \
      --ipconfig0 ip=${CLOUD_INIT_IP} \
      --nameserver ${CLOUD_INIT_NAMESERVER} \
      --ciupgrade 1 \
      --ciuser ${CLOUD_INIT_USER} \
      --cipassword=${CLOUD_INIT_PASSWORD} \
      --cicustom "user=local:snippets/cloud-init-disable-ifnames.yml"

  # Atualizando cloudinit
  qm cloudinit update ${TEMPLATE_ID}

  # Transformar em template
  qm template ${TEMPLATE_ID}

  # Remover a imagem baixada
  rm "${IMAGE_FILE}"
}

# Loop para criar todos os templates
for entry in "${IMAGES_LIST[@]}"; do
  IFS=";" read -r VM_NAME ID_TEMPLATE IMAGE_URL <<< "${entry}"
  create_template "${VM_NAME}" "${ID_TEMPLATE}" "${IMAGE_URL}"
done
