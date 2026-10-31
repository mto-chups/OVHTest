output "deployment_name" { value = kubernetes_deployment_v1.this.metadata[0].name }
output "service_name" { value = try(kubernetes_service_v1.this[0].metadata[0].name, null) }

