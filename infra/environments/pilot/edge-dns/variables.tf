variable "load_balancer_ip" {
  type = string
  validation {
    condition     = can(cidrhost("${var.load_balancer_ip}/32", 0))
    error_message = "load_balancer_ip doit être une adresse IPv4 valide."
  }
}
