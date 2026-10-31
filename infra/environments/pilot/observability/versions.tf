terraform {
  required_version = "= 1.17.1"
  backend "s3" {}
  required_providers {
    ovh        = { source = "ovh/ovh", version = "= 2.22.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "= 3.3.0" }
    helm       = { source = "hashicorp/helm", version = "= 3.3.0" }
  }
}
provider "ovh" { endpoint = "ovh-eu" }
provider "kubernetes" { config_path = var.kubeconfig_path }
provider "helm" { kubernetes = { config_path = var.kubeconfig_path } }
