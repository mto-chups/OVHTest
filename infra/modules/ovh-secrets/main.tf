resource "ovh_okms" "this" {
  display_name   = var.display_name
  region         = var.region
  ovh_subsidiary = var.ovh_subsidiary

  lifecycle {
    prevent_destroy = true
  }
}
