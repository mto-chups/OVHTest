module "cluster" {
  source = "../../../modules/ovh-mks"

  service_name             = var.service_name
  name                     = "ovhtest-pilot"
  region                   = "GRA11"
  kubernetes_version       = "1.34"
  plan                     = "free"
  network_id               = var.node_network_id
  nodes_subnet_id          = var.nodes_subnet_id
  load_balancers_subnet_id = var.load_balancers_subnet_id
  pods_cidr                = "10.42.0.0/16"
  services_cidr            = "10.43.0.0/16"
  admin_cidrs              = var.admin_cidrs
  flavor_name              = "b3-8"
  min_nodes                = 1
  desired_nodes            = 1
  max_nodes                = 2
}
