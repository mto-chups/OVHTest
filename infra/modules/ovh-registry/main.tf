resource "ovh_cloud_project_containerregistry" "this" {
  service_name = var.service_name
  name         = var.name
  region       = var.region
  plan_id      = var.plan_id
}
