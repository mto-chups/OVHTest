terraform {
  required_providers {
    ovh        = { source = "ovh/ovh" }
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}
