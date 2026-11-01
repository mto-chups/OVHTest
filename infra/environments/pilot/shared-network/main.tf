module "network" {
  source = "../../../modules/ovh-network"

  service_name = var.service_name
  vrack_id     = var.vrack_id
  create_vrack = var.create_vrack
  name         = "ovhtest-pilot"
  vlan_id      = var.vlan_id
  node_region  = "GRA11"
  # Private Network accepts the OpenStack datacenter code. Managed databases
  # use the separate service-region label "GRA" when they attach this network.
  data_region         = "GRA11"
  nodes_cidr          = "10.40.0.0/24"
  load_balancers_cidr = "10.40.1.0/24"
  data_cidr           = "10.40.2.0/24"
}
