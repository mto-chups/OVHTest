resource "ovh_cloud_project_database" "this" {
  service_name        = var.service_name
  description         = var.description
  engine              = "postgresql"
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

resource "ovh_cloud_project_database_database" "application" {
  service_name = var.service_name
  engine       = ovh_cloud_project_database.this.engine
  cluster_id   = ovh_cloud_project_database.this.id
  name         = var.database_name
}
