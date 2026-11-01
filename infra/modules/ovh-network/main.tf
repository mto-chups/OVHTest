check "vrack_source" {
  assert {
    condition     = (var.vrack_id != null) != var.create_vrack
    error_message = "Définissez vrack_id ou create_vrack=true, mais pas les deux."
  }
}

resource "ovh_vrack" "this" {
  count          = var.create_vrack ? 1 : 0
  ovh_subsidiary = "FR"
  name           = "${var.name}-vrack"
  description    = "vRack du pilote OVHTest"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  vrack_id = var.create_vrack ? ovh_vrack.this[0].service_name : var.vrack_id
}

resource "ovh_vrack_cloudproject" "project" {
  service_name = local.vrack_id
  project_id   = var.service_name
}

resource "ovh_cloud_project_network_private" "this" {
  service_name = var.service_name
  name         = var.name
  regions      = [var.node_region, var.data_region]
  vlan_id      = var.vlan_id

  depends_on = [ovh_vrack_cloudproject.project]
}

locals {
  node_network_id = ovh_cloud_project_network_private.this.regions_openstack_ids[var.node_region]
  data_network_id = ovh_cloud_project_network_private.this.regions_openstack_ids[var.data_region]
}

resource "ovh_cloud_project_network_private_subnet_v2" "nodes" {
  service_name                    = var.service_name
  network_id                      = local.node_network_id
  region                          = var.node_region
  name                            = "${var.name}-nodes"
  cidr                            = var.nodes_cidr
  dhcp                            = true
  enable_gateway_ip               = true
  use_default_public_dns_resolver = true
}

resource "ovh_cloud_project_network_private_subnet_v2" "load_balancers" {
  service_name                    = var.service_name
  network_id                      = local.node_network_id
  region                          = var.node_region
  name                            = "${var.name}-load-balancers"
  cidr                            = var.load_balancers_cidr
  dhcp                            = true
  enable_gateway_ip               = true
  use_default_public_dns_resolver = true
}

resource "ovh_cloud_project_network_private_subnet_v2" "data" {
  service_name                    = var.service_name
  network_id                      = local.data_network_id
  region                          = var.data_region
  name                            = "${var.name}-data"
  cidr                            = var.data_cidr
  dhcp                            = true
  enable_gateway_ip               = false
  use_default_public_dns_resolver = true
}

resource "ovh_cloud_project_gateway" "egress" {
  service_name = var.service_name
  name         = "${var.name}-egress"
  model        = var.gateway_model
  region       = var.node_region
  network_id   = local.node_network_id
  subnet_id    = ovh_cloud_project_network_private_subnet_v2.load_balancers.id
}
