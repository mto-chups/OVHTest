variable "service_name" { type = string }
variable "description" { type = string }
variable "engine_version" { type = string }
variable "plan" { type = string }
variable "flavor" { type = string }
variable "region" { type = string }
variable "network_id" { type = string }
variable "subnet_id" { type = string }
variable "database_name" {
  type    = string
  default = "ovhtest"
}
