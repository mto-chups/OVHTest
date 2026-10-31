output "available_regions" { value = data.ovh_cloud_project_regions.available.names }
output "gra11_flavors" { value = data.ovh_cloud_project_flavors.gra11.flavors }
output "gra11_quota" { value = data.ovh_cloud_quota.gra11 }
output "database_engines" { value = data.ovh_cloud_project_database_capabilities.databases.engines }
output "database_plans" { value = data.ovh_cloud_project_database_capabilities.databases.plans }
output "database_flavors" { value = data.ovh_cloud_project_database_capabilities.databases.flavors }
output "registry_capabilities" { value = data.ovh_cloud_project_capabilities_containerregistry.registry.result }
