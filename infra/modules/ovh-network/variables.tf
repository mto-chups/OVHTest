variable "service_name" { type = string }
variable "vrack_id" {
  type    = string
  default = null
}
variable "create_vrack" {
  type    = bool
  default = false
}
variable "name" { type = string }
variable "vlan_id" { type = number }
variable "node_region" { type = string }
variable "data_region" { type = string }
variable "nodes_cidr" { type = string }
variable "load_balancers_cidr" { type = string }
variable "data_cidr" { type = string }
variable "gateway_model" {
  type    = string
  default = "s"
}
