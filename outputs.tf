output "Load_Balancer_Stats" {
  value = "http://localhost:8080/stats"
}

output "vault_address" {
  value = "export VAULT_ADDR=https://localhost:8200"
}

output "CA_Cert" {
  value = "export VAULT_CACERT=${path.module}/config/vault-server.crt"
}

output "Keys" {
  value = "${path.module}/keys.json"
}