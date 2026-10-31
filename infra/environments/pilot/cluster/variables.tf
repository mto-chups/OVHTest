variable "service_name" {
  type    = string
  default = "032692ab7ad4437f9140d11b371eb451"
}
variable "node_network_id" { type = string }
variable "nodes_subnet_id" { type = string }
variable "load_balancers_subnet_id" { type = string }
variable "admin_cidrs" { type = set(string) }
