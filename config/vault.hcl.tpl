ui = true
log_level = "trace"

api_addr = "https://${name}:8200"
cluster_addr = "https://${name}:8201"

storage "raft" {
  path    = "/vault/data"
  node_id = "${name}"
  retry_join {
    leader_api_addr = "https://vault-node-1:8200"
    leader_ca_cert_file = "/vault/config/vault-server.crt"
    leader_client_cert_file = "/vault/config/vault-server.crt"
    leader_client_key_file = "/vault/config/vault-server.key"
  }
  retry_join {
    leader_api_addr = "https://vault-node-2:8200"
    leader_ca_cert_file = "/vault/config/vault-server.crt"
    leader_client_cert_file = "/vault/config/vault-server.crt"
    leader_client_key_file = "/vault/config/vault-server.key"
  }
  retry_join {
    leader_api_addr = "https://vault-node-3:8200"
    leader_ca_cert_file = "/vault/config/vault-server.crt"
    leader_client_cert_file = "/vault/config/vault-server.crt"
    leader_client_key_file = "/vault/config/vault-server.key"
  }
}

listener "tcp" {
  address         = "${name}:8200"
  tls_cert_file   = "/vault/config/vault-server.crt"
  tls_key_file    = "/vault/config/vault-server.key"
}

seal "transit" {
  address = "http://vault-transit:8200"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  token = "${vault_token}"
}

