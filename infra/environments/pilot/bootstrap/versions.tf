terraform {
  required_version = "= 1.17.1"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "= 2.22.0"
    }
  }
}

provider "ovh" {
  endpoint = "ovh-eu"
}
