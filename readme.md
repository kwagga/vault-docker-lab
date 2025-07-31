# Dry run example

## Requirements

* Docker 
* Terraform 1.9.5
* Vault Enterprise License
* OpenSSL

## Setup

Grab the source
```
git clone https://github.com/kwagga/dry-run-cert
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

Wait for 1 hour
```
vault status
```

## Issue
Can't login or do any operations due to expired certificate
```
❯ vault status
Error checking seal status: Get "https://127.0.0.1:8200/v1/sys/seal-status": tls: failed to verify certificate: x509: certificate has expired or is not yet valid: current time 2024-09-19T14:22:57+02:00 is after 2024-09-19T11:24:05Z
```

## Fix
Generate a new certificate and key

Check current certificate (note SAN)
```
openssl x509 -in config/vault-server.crt -noout -text
```

Generate a new certificate and key pair
```
cd  fix
terraform init
terraform apply
```

Copy cert back to Vault config
```
cp -rv cert/* ../config/
```

Restart Vault containers:

```
docker restart vault-node-[1,2,3]
vault status
```

## Cleanup

```
terraform destroy
```

## Additional commands

Open terminal session to each of the Vault nodes using:

```
docker exec -it vault-node-1 /bin/sh
export VAULT_ADDR=https://vault-node-1:8200
export VAULT_CACERT=/vault/config/vault-server.crt
vault status
```

