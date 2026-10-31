output "traefik_namespace" { value = kubernetes_namespace_v1.traefik.metadata[0].name }
output "external_secrets_namespace" { value = kubernetes_namespace_v1.external_secrets.metadata[0].name }

