output "cluster_id" { value = ovh_cloud_project_database.this.id }
output "database_name" { value = ovh_cloud_project_database_database.application.name }
output "endpoints" { value = ovh_cloud_project_database.this.endpoints }

