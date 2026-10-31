variable "service_name" {
  description = "Identifiant du projet Public Cloud OVHcloud."
  type        = string
  default     = "032692ab7ad4437f9140d11b371eb451"
}

variable "region" {
  type    = string
  default = "GRA"
}

variable "bucket_name" {
  type    = string
  default = "ovhtest-tfstate-032692ab"
}
