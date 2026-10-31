resource "ovh_cloud_project_database" "this" {
  service_name        = var.service_name
  description         = var.description
  engine              = "valkey"
  version             = var.engine_version
  plan                = var.plan
  flavor              = var.flavor
  deletion_protection = true

  nodes {
    region     = var.region
    network_id = var.network_id
    subnet_id  = var.subnet_id
  }

  lifecycle {
    prevent_destroy = true
  }
}
