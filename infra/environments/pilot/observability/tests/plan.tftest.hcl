mock_provider "ovh" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
run "observability_plan" {
  command = plan
  variables {
    kubeconfig_path       = "kubeconfig-test"
    ldp_service_name      = "ldp-test"
    retention_id          = "retention-test"
    ldp_host              = "gra1.logs.ovh.com"
    kube_id               = "kube-test"
    postgresql_cluster_id = "postgres-test"
    valkey_cluster_id     = "valkey-test"
  }
}
