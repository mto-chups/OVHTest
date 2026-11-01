resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_service_account_v1" "workload" {
  for_each = var.service_accounts
  metadata {
    name      = each.value
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  automount_service_account_token = false
}

resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "pilot-quota"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    hard = {
      "limits.cpu"      = "4"
      "limits.memory"   = "6Gi"
      "requests.cpu"    = "1"
      "requests.memory" = "2Gi"
      pods              = "12"
    }
  }
}

resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "pilot-defaults"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "500m", memory = "512Mi" }
      default_request = { cpu = "100m", memory = "128Mi" }
    }
  }
}

resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "dns" {
  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "kube-system" } }
        pod_selector { match_labels = { "k8s-app" = "kube-dns" } }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "internal" {
  metadata {
    name      = "allow-namespace-internal"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
    ingress {
      from {
        pod_selector {}
      }
    }
    egress {
      to {
        pod_selector {}
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "data" {
  metadata {
    name      = "allow-private-data-services"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      to {
        ip_block {
          cidr = var.data_cidr
        }
      }
      ports {
        port     = "20184"
        protocol = "TCP"
      }
      ports {
        port     = "20185"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "https" {
  metadata {
    name      = "allow-https-egress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "traefik" {
  metadata {
    name      = "allow-traefik-to-server"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector { match_labels = { "app.kubernetes.io/name" = "server" } }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "traefik" }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "cert_manager_solver" {
  metadata {
    name      = "allow-traefik-to-cert-manager-solver"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = { "acme.cert-manager.io/http01-solver" = "true" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "traefik" }
        }
      }
    }
  }
}
