data "ovh_cloud_project_regions" "available" {
  service_name = var.service_name
}

data "ovh_cloud_project_flavors" "gra11" {
  service_name = var.service_name
  region       = "GRA11"
}

data "ovh_cloud_quota" "gra11" {
  service_name = var.service_name
  region       = "GRA11"
}

data "ovh_cloud_project_database_capabilities" "databases" {
  service_name = var.service_name
}

data "ovh_cloud_project_capabilities_containerregistry" "registry" {
  service_name = var.service_name
}
