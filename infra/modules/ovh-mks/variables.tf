variable "service_name" { type = string }
variable "name" { type = string }
variable "region" { type = string }
variable "kubernetes_version" { type = string }
variable "plan" { type = string }
variable "network_id" { type = string }
variable "nodes_subnet_id" { type = string }
variable "load_balancers_subnet_id" { type = string }
variable "pods_cidr" { type = string }
variable "services_cidr" { type = string }
variable "admin_cidrs" {
  type = set(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "Au moins un CIDR administrateur précis est requis ; 0.0.0.0/0 est interdit."
  }
}
variable "flavor_name" { type = string }
variable "min_nodes" { type = number }
variable "max_nodes" { type = number }
variable "desired_nodes" { type = number }
