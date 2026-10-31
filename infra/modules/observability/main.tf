resource "ovh_dbaas_logs_output_graylog_stream" "application" {
  service_name       = var.ldp_service_name
  title              = "ovhtest-pilot"
  description        = "Logs Kubernetes du pilote OVHTest"
  retention_id       = var.retention_id
  indexing_enabled   = true
  web_socket_enabled = true
}

resource "ovh_cloud_project_kube_log_subscription" "audit" {
  count        = var.enable_mks_audit_logs ? 1 : 0
  service_name = var.service_name
  kube_id      = var.kube_id
  kind         = var.mks_log_kind
  stream_id    = ovh_dbaas_logs_output_graylog_stream.application.id
}

resource "ovh_cloud_project_database_log_subscription" "postgresql" {
  count        = var.enable_database_logs ? 1 : 0
  service_name = var.service_name
  cluster_id   = var.postgresql_cluster_id
  engine       = "postgresql"
  kind         = var.postgresql_log_kind
  stream_id    = ovh_dbaas_logs_output_graylog_stream.application.id
}

resource "ovh_cloud_project_database_log_subscription" "valkey" {
  count        = var.enable_database_logs ? 1 : 0
  service_name = var.service_name
  cluster_id   = var.valkey_cluster_id
  engine       = "valkey"
  kind         = var.valkey_log_kind
  stream_id    = ovh_dbaas_logs_output_graylog_stream.application.id
}

resource "kubernetes_namespace_v1" "logging" {
  metadata {
    name = "logging"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    annotations = {
      "ovhtest/security-exception" = "Fluent Bit DaemonSet requires host log mounts"
    }
  }
}

resource "kubernetes_manifest" "ldp_token" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "ldp-token", namespace = kubernetes_namespace_v1.logging.metadata[0].name }
    spec = {
      refreshInterval = "5m"
      secretStoreRef  = { name = "ovhcloud", kind = "ClusterSecretStore" }
      target          = { name = "ldp-token", creationPolicy = "Owner" }
      data = [{
        secretKey = "ldp-token"
        remoteRef = { key = "pilot/shared/ldp", property = "token" }
      }]
    }
  }
}

resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  namespace  = kubernetes_namespace_v1.logging.metadata[0].name
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.fluent_bit_chart_version
  atomic     = true
  wait       = true

  values = [yamlencode({
    env = [{
      name      = "FLUENT_LDP_TOKEN"
      valueFrom = { secretKeyRef = { name = "ldp-token", key = "ldp-token" } }
    }]
    config = {
      filters = <<-EOT
        [FILTER]
            Name kubernetes
            Match kube.*
            Merge_Log On
            Keep_Log Off
            K8S-Logging.Parser On
            K8S-Logging.Exclude On

        [FILTER]
            Name record_modifier
            Match kube.*
            Record X-OVH-TOKEN $${FLUENT_LDP_TOKEN}

        [FILTER]
            Name nest
            Match kube.*
            Wildcard pod_name container_name namespace_name
            Operation lift
            Nested_under kubernetes
            Add_prefix kubernetes_

        [FILTER]
            Name modify
            Match kube.*
            Copy kubernetes_pod_name host
            Add log none
      EOT
      outputs = <<-EOT
        [OUTPUT]
            Name gelf
            Match kube.*
            Host ${var.ldp_host}
            Port 12202
            Mode tls
            tls On
            tls.verify On
            Compress False
            Gelf_Short_Message_Key log
      EOT
    }
  })]

  depends_on = [kubernetes_manifest.ldp_token]
}
