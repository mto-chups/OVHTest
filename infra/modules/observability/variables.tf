variable "service_name" { type = string }
variable "ldp_service_name" { type = string }
variable "retention_id" { type = string }
variable "ldp_host" { type = string }
variable "kube_id" { type = string }
variable "postgresql_cluster_id" { type = string }
variable "valkey_cluster_id" { type = string }
variable "enable_mks_audit_logs" {
  type    = bool
  default = false
}
variable "enable_database_logs" {
  type    = bool
  default = false
}
variable "mks_log_kind" {
  type    = string
  default = "audit"
}
variable "postgresql_log_kind" {
  type    = string
  default = "service"
}
variable "valkey_log_kind" {
  type    = string
  default = "service"
}
variable "fluent_bit_chart_version" { type = string }
