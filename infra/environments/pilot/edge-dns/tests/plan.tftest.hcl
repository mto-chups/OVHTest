mock_provider "ovh" {}
run "dns_plan" {
  command = plan
  variables { load_balancer_ip = "203.0.113.20" }
}
