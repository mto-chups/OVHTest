output "fqdn" { value = "${ovh_domain_zone_record.pilot.subdomain}.${ovh_domain_zone_record.pilot.zone}" }
