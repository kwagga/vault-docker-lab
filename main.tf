terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.20.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.3"
    }
  }
}

data "external" "docker_host" {
  program = ["sh", "-c", "docker context inspect -f json | jq -r '{host: (.[].Endpoints.docker.Host)}'"]
}

provider "docker" {
  host = data.external.docker_host.result.host
}

provider "vault" {
  address = "http://127.0.0.1:8210"
  token = "root"
}

resource "docker_network" "vault_network" {
  name   = "vault-network"
  driver = "bridge"
}

# Generate Self-Signed Certificates
resource "tls_private_key" "vault_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "vault_cert" {
  private_key_pem = tls_private_key.vault_key.private_key_pem

  subject {
    common_name  = "vault.localhost"
    organization = "Vault-Docker-Lab"
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [
    "vault-node-1",
    "vault-node-2",
    "vault-node-3",
    "localhost"
  ]

  validity_period_hours = 17520
}

# HAProxy configuration creation using "local_file" resource
resource "local_file" "haproxy_config" {
  filename = abspath("${local.config_dir}/haproxy.cfg")

  content = <<-EOT
    global
      log stdout format raw local0

    defaults
      log global
      timeout connect 5000ms
      timeout client  50000ms
      timeout server  50000ms

    frontend stats
        mode http
        bind *:8080
        stats enable
        stats uri /stats
        stats refresh 10s

    frontend vault_frontend
      bind *:8200
      mode tcp

      # Prioritize TCP check backend if available
      use_backend vault_backend_tcp if { nbsrv(vault_backend_tcp) gt 0 }

      # Fallback to HTTP check backend if HTTP servers are available
      use_backend vault_backend_http if { nbsrv(vault_backend_http) gt 0 }

      # Fallback to default backend if no other conditions match
      default_backend vault_backend_tcp

    # Backend with TCP health checks (for initial availability)
    backend vault_backend_tcp
      mode tcp
      balance roundrobin
      option tcp-check

      # Define TCP check for each server
      server vault-node-1 vault-node-1:8200 check
      server vault-node-2 vault-node-2:8200 check
      server vault-node-3 vault-node-3:8200 check

    # Backend with HTTP health checks (for routing after HTTP is available)
    backend vault_backend_http
      mode http
      balance roundrobin
      option httpchk GET /v1/sys/health
      http-check expect status 200

      # Use SSL for the HTTP health check since the endpoint is HTTPS
      server vault-node-1 vault-node-1:8200 check ssl verify none
      server vault-node-2 vault-node-2:8200 check ssl verify none
      server vault-node-3 vault-node-3:8200 check ssl verify none

  EOT
}

# We leverage a dev mode single node to provide transit
resource "docker_container" "vault_transit" {
  name = "vault-transit"
  image = "hashicorp/vault-enterprise:latest"

  networks_advanced {
    name = docker_network.vault_network.name
  }

  ports {
    internal = 8200
    external = 8210
  }  

  env = [
    "VAULT_ADDR=http://127.0.0.1:8200",
    "VAULT_LICENSE=${var.vault_enterprise_license}",
    "VAULT_DEV_ROOT_TOKEN_ID=root"
  ]

  depends_on = [
    docker_network.vault_network
  ]
}

resource "local_file" "vault_config" {
  for_each = toset(["vault-node-1", "vault-node-2", "vault-node-3"])
  filename = abspath("${local.config_dir}/${each.value}.hcl")
  content = templatefile("${local.config_dir}/vault.hcl.tpl", {
    name = each.value
    vault_token = vault_token.autounseal.client_token 
  })
  depends_on = [vault_token.autounseal]

}

#Provision transit

resource "vault_mount" "transit" {
  path                      = "transit"
  type                      = "transit"
  description               = "Transit for unseal"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
  depends_on = [ docker_container.vault_transit ]
}

resource "vault_transit_secret_backend_key" "key" {
  backend = vault_mount.transit.path
  name    = "autounseal"
  deletion_allowed = "true"
  depends_on = [ vault_mount.transit ]
}

resource "vault_policy" "autounsealpol" {
  name = "autounseal"

  policy = <<EOT
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}
path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
EOT

depends_on = [ docker_container.vault_transit ]

}

resource "vault_token" "autounseal" {
  policies = ["autounseal", "default"]
  period = "24h"
  metadata = {
    "purpose" = "autounseal"
  }
  depends_on = [ vault_transit_secret_backend_key.key, vault_policy.autounsealpol, vault_mount.transit ]
}


# Vault Nodes
resource "docker_container" "vault_node" {
  count = 3

  name = "vault-node-${count.index + 1}"

  image = "hashicorp/vault-enterprise:latest"

  networks_advanced {
    name = docker_network.vault_network.name
  }

  command = ["server"]

  volumes {
    host_path      = abspath("${path.module}/data/node-${count.index + 1}")
    container_path = "/vault/data"
  }

  volumes {
    host_path      = abspath("${local.config_dir}/vault-node-${count.index + 1}.hcl")
    container_path = "/vault/config/vault.hcl"
  }

  volumes {
    host_path      = abspath("${path.module}/config/vault-server.key")
    container_path = "/vault/config/vault-server.key"
  }

  volumes {
    host_path      = abspath("${path.module}/config/vault-server.crt")
    container_path = "/vault/config/vault-server.crt"
  }

  volumes {
    host_path      = abspath("${local.scripts_dir}")
    container_path = "/scripts"
  }

  env = ["VAULT_LICENSE=${var.vault_enterprise_license}"]

  depends_on = [
    docker_network.vault_network, local_file.vault_config, null_resource.write_tls_cert
  ]
}

# Load Balancer Container
resource "docker_container" "vault_lb" {
  name  = "vault-lb"
  image = "haproxy:latest"

  networks_advanced {
    name = docker_network.vault_network.name
  }

  ports {
    internal = 8200
    external = 8200
  }

    ports {
    internal = 8080
    external = 8080
  }

  volumes {
    host_path      = "${local_file.haproxy_config.filename}"
    container_path = "/usr/local/etc/haproxy/haproxy.cfg"
  }

# Explicitly run haproxy with the config file
  command = [
    "haproxy", 
    "-f", "/usr/local/etc/haproxy/haproxy.cfg"
  ]

  depends_on = [
    docker_network.vault_network,
    local_file.haproxy_config,
    docker_container.vault_node
  ]

  provisioner "local-exec" {
    command = <<-EOT
    set -e
    vault operator init -format=json -recovery-shares=1 -recovery-threshold=1 >> keys.json
    EOT

    environment = {
    VAULT_ADDR = "https://localhost:8200"
    VAULT_CACERT   = "${local.config_dir}/vault-server.crt"
    VAULT_SKIP_VERIFY = "true"
  }
  }
}

locals {
  config_dir  = abspath("${path.module}/config")
  scripts_dir = abspath("${path.module}")
}

resource "null_resource" "create_config_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.config_dir}"
  }
}

resource "null_resource" "delete_data_on_destroy" {
  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf ${path.module}/data ${path.module}/keys.json"
  }
}

resource "null_resource" "write_tls_cert" {
provisioner "local-exec" {
    command = <<-EOT
      mkdir -p "${path.module}/config"
      [ -d "./config/vault-server.key" ] && rm -rf "./config/vault-server.key"
      [ -d "./config/vault-server.crt" ] && rm -rf "./config/vault-server.crt"
      echo '${tls_private_key.vault_key.private_key_pem}' > "${path.module}/config/vault-server.key"
      echo '${tls_self_signed_cert.vault_cert.cert_pem}' > "${path.module}/config/vault-server.crt"
    EOT
  }
}
