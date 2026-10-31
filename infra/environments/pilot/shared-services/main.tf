module "postgresql" {
  source = "../../../modules/ovh-postgresql"

  service_name   = var.service_name
  description    = "ovhtest-pilot-postgresql"
  engine_version = var.postgresql_version
  plan           = var.postgresql_plan
  flavor         = var.postgresql_flavor
  region         = "GRA"
  network_id     = var.data_network_id
  subnet_id      = var.data_subnet_id
}

module "valkey" {
  source = "../../../modules/ovh-valkey"

  service_name   = var.service_name
  description    = "ovhtest-pilot-valkey"
  engine_version = var.valkey_version
  plan           = var.valkey_plan
  flavor         = var.valkey_flavor
  region         = "GRA"
  network_id     = var.data_network_id
  subnet_id      = var.data_subnet_id
}

module "registry" {
  source = "../../../modules/ovh-registry"

  service_name = var.service_name
  name         = "ovhtest-pilot"
  region       = "GRA"
  plan_id      = var.registry_plan_id
}

module "secrets" {
  source = "../../../modules/ovh-secrets"

  display_name = "ovhtest-pilot"
  region       = var.okms_region
}
