mock_provider "kubernetes" {}
mock_provider "helm" {}
run "platform_plan" {
  command = plan
  variables {
    kubeconfig_path = "kubeconfig-test"
    okms_id         = "00000000-0000-0000-0000-000000000000"
    okms_server     = "https://eu-west-rbx.okms.ovh.net"
  }
}
