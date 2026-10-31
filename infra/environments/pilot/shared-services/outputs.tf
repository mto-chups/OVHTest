output "postgresql_cluster_id" { value = module.postgresql.cluster_id }
output "postgresql_endpoints" { value = module.postgresql.endpoints }
output "valkey_cluster_id" { value = module.valkey.cluster_id }
output "valkey_endpoints" { value = module.valkey.endpoints }
output "registry_id" { value = module.registry.registry_id }
output "registry_url" { value = module.registry.registry_url }
output "okms_id" { value = module.secrets.okms_id }
output "okms_rest_endpoint" { value = module.secrets.rest_endpoint }
