resource "ovh_domain_zone_record" "pilot" {
  zone      = "minesave.fr"
  subdomain = "pilot"
  fieldtype = "A"
  target    = var.load_balancer_ip
  ttl       = 300
}
