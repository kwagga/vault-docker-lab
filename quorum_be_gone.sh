#!/bin/bash
# This is fire up the lab and break quorum.

terraform init
terraform apply --auto-approve
sleep 10
export VAULT_CACERT=config/vault-server.crt
export VAULT_ADDR=https://localhost:8200
vault login $(jq -r '.root_token' keys.json)
vault status
docker stop vault-node-1 vault-node-2 vault-node-3
rm -rf data/node-1 data/node-2
docker start vault-node-1 vault-node-2 vault-node-3
