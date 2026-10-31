resource "ovh_cloud_project_kube" "this" {
  service_name             = var.service_name
  name                     = var.name
  region                   = var.region
  version                  = var.kubernetes_version
  plan                     = var.plan
  private_network_id       = var.network_id
  nodes_subnet_id          = var.nodes_subnet_id
  load_balancers_subnet_id = var.load_balancers_subnet_id
  update_policy            = "NEVER_UPDATE"

  ip_allocation_policy {
    pods_ipv4_cidr     = var.pods_cidr
    services_ipv4_cidr = var.services_cidr
  }
}

resource "ovh_cloud_project_kube_nodepool" "workers" {
  service_name   = var.service_name
  kube_id        = ovh_cloud_project_kube.this.id
  name           = "workers"
  flavor_name    = var.flavor_name
  desired_nodes  = var.desired_nodes
  min_nodes      = var.min_nodes
  max_nodes      = var.max_nodes
  autoscale      = true
  monthly_billed = false
  anti_affinity  = false
}

resource "ovh_cloud_project_kube_iprestrictions" "administrators" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = var.admin_cidrs
}
