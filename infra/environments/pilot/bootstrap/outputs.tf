output "bucket_name" {
  value = ovh_cloud_project_storage.terraform_state.name
}

output "region" {
  value = var.region
}
