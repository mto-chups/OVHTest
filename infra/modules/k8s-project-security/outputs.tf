output "namespace" { value = kubernetes_namespace_v1.this.metadata[0].name }
output "service_accounts" { value = { for key, value in kubernetes_service_account_v1.workload : key => value.metadata[0].name } }

