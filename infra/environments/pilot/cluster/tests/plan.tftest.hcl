mock_provider "ovh" {}
run "cluster_plan" {
  command = plan
  variables {
    node_network_id          = "network-test"
    nodes_subnet_id          = "nodes-test"
    load_balancers_subnet_id = "lb-test"
    admin_cidrs              = ["203.0.113.10/32"]
  }
}
