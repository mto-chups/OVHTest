resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = { "app.kubernetes.io/name" = var.name }
  }

  spec {
    replicas = 1
    strategy {
      type = "RollingUpdate"
    }
    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }
    template {
      metadata {
        labels      = { "app.kubernetes.io/name" = var.name }
        annotations = { "ovhtest/secret-revision" = var.secret_revision }
      }
      spec {
        service_account_name            = var.service_account_name
        automount_service_account_token = false
        enable_service_links            = false
        image_pull_secrets {
          name = var.image_pull_secret
        }
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name              = var.name
          image             = var.image
          image_pull_policy = "IfNotPresent"
          command           = var.command
          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }
          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "env_from" {
            for_each = toset(var.env_from_secrets)
            content {
              secret_ref {
                name = env_from.value
              }
            }
          }
          readiness_probe {
            http_get {
              path = var.readiness_path
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = var.liveness_path
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }
          security_context {
            run_as_non_root            = true
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "this" {
  count = var.create_service ? 1 : 0
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    type     = "ClusterIP"
    selector = { "app.kubernetes.io/name" = var.name }
    port {
      name        = "http"
      port        = var.port
      target_port = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  count = var.hpa_enabled ? 1 : 0
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}
