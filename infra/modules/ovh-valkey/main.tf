resource "ovh_cloud_project_database" "this" {
  service_name = var.service_name
  description  = var.description
  engine       = "valkey"
  version      = var.engine_version
  plan         = var.plan
  flavor       = var.flavor
  # Fin du pilote : la protection OVH doit être désactivée par un apply
  # dédié avant que le plan de destruction puisse supprimer le service.
  deletion_protection = false

  nodes {
    region     = var.region
    network_id = var.network_id
    subnet_id  = var.subnet_id
  }

  ip_restrictions {
    description = "Kubernetes nodes"
    ip          = "10.40.0.0/24"
  }

  ip_restrictions {
    description = "Kubernetes pods"
    ip          = "10.42.0.0/16"
  }

  ip_restrictions {
    description = "MKS pod network"
    ip          = "10.2.0.0/16"
  }
}
