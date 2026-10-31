module "observability" {
  source = "../../../modules/observability"

  service_name             = var.service_name
  ldp_service_name         = var.ldp_service_name
  retention_id             = var.retention_id
  ldp_host                 = var.ldp_host
  kube_id                  = var.kube_id
  postgresql_cluster_id    = var.postgresql_cluster_id
  valkey_cluster_id        = var.valkey_cluster_id
  enable_mks_audit_logs    = var.enable_mks_audit_logs
  enable_database_logs     = var.enable_database_logs
  mks_log_kind             = var.mks_log_kind
  postgresql_log_kind      = var.postgresql_log_kind
  valkey_log_kind          = var.valkey_log_kind
  fluent_bit_chart_version = "0.58.3"
}
