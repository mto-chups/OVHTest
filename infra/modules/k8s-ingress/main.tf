resource "kubernetes_ingress_v1" "this" {
  metadata {
    name      = "ovhtest"
    namespace = var.namespace
    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-production"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
    }
  }
  spec {
    ingress_class_name = "traefik"
    tls {
      hosts       = [var.host]
      secret_name = "pilot-minesave-fr-tls"
    }
    rule {
      host = var.host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.service_name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}
