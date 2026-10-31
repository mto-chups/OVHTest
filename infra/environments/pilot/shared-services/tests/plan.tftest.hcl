mock_provider "ovh" {}
run "services_plan" {
  command = plan
  variables {
    data_network_id    = "network-test"
    data_subnet_id     = "subnet-test"
    postgresql_version = "17"
    postgresql_flavor  = "db1-4"
    valkey_version     = "8.0"
    valkey_flavor      = "db1-4"
    registry_plan_id   = "plan-test"
  }
}
