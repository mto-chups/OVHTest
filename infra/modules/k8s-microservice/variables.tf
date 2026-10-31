variable "name" { type = string }
variable "namespace" { type = string }
variable "service_account_name" { type = string }
variable "image" {
  type = string
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image))
    error_message = "L'image doit être référencée par digest sha256 immuable."
  }
}
variable "command" { type = list(string) }
variable "port" { type = number }
variable "env" {
  type    = map(string)
  default = {}
}
variable "env_from_secrets" {
  type    = list(string)
  default = []
}
variable "image_pull_secret" { type = string }
variable "create_service" {
  type    = bool
  default = false
}
variable "readiness_path" {
  type    = string
  default = "/health"
}
variable "liveness_path" {
  type    = string
  default = "/health"
}
variable "secret_revision" {
  type    = string
  default = "1"
}
variable "resources" {
  type = object({
    requests = map(string)
    limits   = map(string)
  })
}
variable "hpa_enabled" {
  type    = bool
  default = false
}
variable "hpa_min_replicas" {
  type    = number
  default = 1
}
variable "hpa_max_replicas" {
  type    = number
  default = 2
}
