variable "kubeconfig_path" { type = string }
variable "image" { type = string }
variable "fqdn" {
  type    = string
  default = "pilot.minesave.fr"
}
variable "secret_revision" {
  type    = string
  default = "1"
}
variable "runtime_db_user" {
  type    = string
  default = "ovhtest_runtime"
}
