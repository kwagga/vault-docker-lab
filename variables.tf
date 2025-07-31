# variables.tf
variable "vault_enterprise_license" {
  type = string
  description = "Vault Enterprise license string"
}

variable "docker_host" {
  description = "Docker daemon socket path"
  type        = string
  default     = "unix:///var/run/docker.sock"
}