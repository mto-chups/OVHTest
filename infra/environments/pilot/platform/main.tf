module "platform" {
  source = "../../../modules/k8s-platform"

  okms_id                        = var.okms_id
  okms_server                    = var.okms_server
  letsencrypt_email              = "mat.chupin@live.fr"
  traefik_chart_version          = "41.6.1"
  cert_manager_chart_version     = "1.21.2"
  external_secrets_chart_version = "2.13.0"
}
