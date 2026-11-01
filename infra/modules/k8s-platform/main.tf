resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = kubernetes_namespace_v1.traefik.metadata[0].name
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version
  atomic     = true
  wait       = true
  timeout    = 900

  values = [yamlencode({
    deployment = { replicas = 1 }
    service    = { type = "LoadBalancer" }
    providers = { kubernetesIngress = { enabled = true }, kubernetesCRD = { enabled = true } }
  })]
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  atomic     = true
  wait       = true

  values = [yamlencode({
    crds = { enabled = true }
  })]
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_chart_version
  atomic     = true
  wait       = true

  values = [yamlencode({
    installCRDs = true
  })]
}

resource "helm_release" "platform_config" {
  name      = "platform-config"
  namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  chart     = "${path.module}/chart"
  atomic    = true
  wait      = true

  values = [yamlencode({
    letsencryptEmail         = var.letsencrypt_email
    okmsId                   = var.okms_id
    okmsServer               = var.okms_server
    externalSecretsNamespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  })]

  depends_on = [helm_release.cert_manager, helm_release.traefik, helm_release.external_secrets]
}
