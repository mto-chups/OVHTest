mock_provider "kubernetes" {}
run "applications_plan" {
  command = plan
  variables {
    kubeconfig_path = "kubeconfig-test"
    image           = "registry.example/ovhtest@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
}
