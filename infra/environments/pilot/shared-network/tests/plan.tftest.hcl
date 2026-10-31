mock_provider "ovh" {}
run "network_plan" {
  command = plan
  variables { vrack_id = "pn-test" }
}
