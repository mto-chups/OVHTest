variable "service_name" {
  type    = string
  default = "032692ab7ad4437f9140d11b371eb451"
}
variable "data_network_id" { type = string }
variable "data_subnet_id" { type = string }
variable "postgresql_version" { type = string }
variable "postgresql_plan" {
  type    = string
  default = "essential"
}
variable "postgresql_flavor" { type = string }
variable "valkey_version" { type = string }
variable "valkey_plan" {
  type    = string
  default = "essential"
}
variable "valkey_flavor" { type = string }
variable "registry_plan_id" { type = string }
variable "okms_region" {
  type    = string
  default = "eu-west-rbx"
}
