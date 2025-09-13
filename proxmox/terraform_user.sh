#!/bin/bash

# 1. Criar Role com permissões necessárias para o Terraform
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Datastore.AllocateTemplate Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# 2. Criar Usuário sem senha
pveum user add terraform-prov@pve --keys ''

# 3. Associar a Role ao Usuário
pveum aclmod / -user terraform-prov@pve -role TerraformProv

# 4. Criar API Token para autenticação sem senha
TOKEN_NAME="terraform-token"
API_TOKEN=$(pveum user token add terraform-prov@pve $TOKEN_NAME --privsep 0)

# 5. Exibir Token gerado (anote imediatamente, pois não poderá ser recuperado)
echo "Seu API Token foi gerado com sucesso! Use as credenciais abaixo:"
echo "Usuário: terraform-prov@pve!$TOKEN_NAME"
echo "Token: $API_TOKEN"

echo "Anote o token, pois ele não poderá ser recuperado depois!"
