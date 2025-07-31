# Vault-Docker-Lab

## Requirements

* Docker 
* Terraform 1.9.5
* Vault Enterprise License
* OpenSSL

## Setup

Grab the source
```
git clone https://github.com/kwagga/vault-docker-lab
```

Create and populate `terraform.tfvars`
```
vault_enterprise_license = "xxx"
```

Change to source and initialize
```
terraform init
terraform apply --auto-approve
```

Check Vault Deployment
```
export VAULT_CACERT=config/vault-server.crt
export VAULT_ADDR=https://localhost:8200
vault login $(jq -r '.root_token' keys.json)
vault status
```

## Cleanup

```
terraform destroy
```

## Additional commands

Open terminal session to each of the Vault nodes using:

```
docker exec -it vault-node-[1,2,3] /bin/sh
export VAULT_ADDR=https://vault-node-1:8200
export VAULT_CACERT=/vault/config/vault-server.crt
vault status
```

