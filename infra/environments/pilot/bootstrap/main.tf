resource "ovh_cloud_project_storage" "terraform_state" {
  service_name = var.service_name
  region_name  = var.region
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }

  lifecycle {
    prevent_destroy = true
  }
}
