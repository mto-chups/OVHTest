locals {
  namespace = "ovhtest"
  resources = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

module "security" {
  source = "../../../modules/k8s-project-security"

  namespace        = local.namespace
  service_accounts = ["server", "microservice-1", "microservice-2", "microservice-3", "migration"]
  data_cidr        = "10.40.2.0/24"
}

resource "kubernetes_manifest" "database_runtime" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "database-runtime", namespace = module.security.namespace }
    spec = {
      refreshInterval = "5m"
      secretStoreRef  = { name = "ovhcloud", kind = "ClusterSecretStore" }
      target          = { name = "database-runtime", creationPolicy = "Owner" }
      dataFrom        = [{ extract = { key = "pilot/ovhtest/database-runtime" } }]
    }
  }
}

resource "kubernetes_manifest" "database_migration" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "database-migration", namespace = module.security.namespace }
    spec = {
      refreshInterval = "5m"
      secretStoreRef  = { name = "ovhcloud", kind = "ClusterSecretStore" }
      target          = { name = "database-migration", creationPolicy = "Owner" }
      dataFrom        = [{ extract = { key = "pilot/ovhtest/database-migration" } }]
    }
  }
}

resource "kubernetes_manifest" "valkey" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "valkey", namespace = module.security.namespace }
    spec = {
      refreshInterval = "5m"
      secretStoreRef  = { name = "ovhcloud", kind = "ClusterSecretStore" }
      target          = { name = "valkey", creationPolicy = "Owner" }
      dataFrom        = [{ extract = { key = "pilot/ovhtest/valkey" } }]
    }
  }
}

resource "kubernetes_manifest" "registry_pull" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "registry-pull", namespace = module.security.namespace }
    spec = {
      refreshInterval = "5m"
      secretStoreRef  = { name = "ovhcloud", kind = "ClusterSecretStore" }
      target = {
        name           = "registry-pull"
        creationPolicy = "Owner"
        template       = { type = "kubernetes.io/dockerconfigjson" }
      }
      data = [{
        secretKey = ".dockerconfigjson"
        remoteRef = { key = "pilot/ovhtest/registry-pull", property = ".dockerconfigjson" }
      }]
    }
  }
}

resource "kubernetes_job_v1" "migration" {
  metadata {
    name      = "database-migration-${substr(sha256(var.image), 0, 10)}"
    namespace = module.security.namespace
  }
  spec {
    backoff_limit = 2
    template {
      metadata { labels = { "app.kubernetes.io/name" = "database-migration" } }
      spec {
        restart_policy                  = "Never"
        service_account_name            = module.security.service_accounts["migration"]
        automount_service_account_token = false
        image_pull_secrets {
          name = "registry-pull"
        }
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name    = "migration"
          image   = var.image
          command = ["node", "dist/migrate/index.js"]
          env {
            name  = "DB_RUNTIME_USER"
            value = var.runtime_db_user
          }
          env_from {
            secret_ref {
              name = "database-migration"
            }
          }
          resources {
            requests = local.resources.requests
            limits   = local.resources.limits
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
  wait_for_completion = true
  timeouts {
    create = "10m"
  }
  depends_on = [kubernetes_manifest.database_migration, kubernetes_manifest.registry_pull]
}

module "server" {
  source               = "../../../modules/k8s-microservice"
  name                 = "server"
  namespace            = module.security.namespace
  service_account_name = module.security.service_accounts["server"]
  image                = var.image
  command              = ["node", "dist/server/index.js"]
  port                 = 3000
  env = {
    PORT               = "3000"
    MS1_URL            = "http://microservice-1:3001"
    REDIS_PREFIX       = "ovhtest"
    REDIS_TLS_REQUIRED = "true"
  }
  env_from_secrets  = ["database-runtime", "valkey"]
  image_pull_secret = "registry-pull"
  create_service    = true
  readiness_path    = "/api/health"
  liveness_path     = "/api/live"
  secret_revision   = var.secret_revision
  resources         = local.resources
  hpa_enabled       = false
  depends_on        = [kubernetes_job_v1.migration, kubernetes_manifest.database_runtime, kubernetes_manifest.valkey]
}

module "microservice_1" {
  source               = "../../../modules/k8s-microservice"
  name                 = "microservice-1"
  namespace            = module.security.namespace
  service_account_name = module.security.service_accounts["microservice-1"]
  image                = var.image
  command              = ["node", "dist/microservice-1/index.js"]
  port                 = 3001
  env                  = { PORT = "3001", SERVER_URL = "http://server:3000" }
  image_pull_secret    = "registry-pull"
  create_service       = true
  secret_revision      = var.secret_revision
  resources            = local.resources
  hpa_enabled          = false
  depends_on           = [kubernetes_job_v1.migration]
}

module "microservice_2" {
  source               = "../../../modules/k8s-microservice"
  name                 = "microservice-2"
  namespace            = module.security.namespace
  service_account_name = module.security.service_accounts["microservice-2"]
  image                = var.image
  command              = ["node", "dist/microservice-2/index.js"]
  port                 = 3002
  env                  = { MS2_PORT = "3002", SERVER_URL = "http://server:3000" }
  env_from_secrets     = ["database-runtime"]
  image_pull_secret    = "registry-pull"
  secret_revision      = var.secret_revision
  resources            = local.resources
  hpa_enabled          = false
  depends_on           = [kubernetes_job_v1.migration, kubernetes_manifest.database_runtime]
}

module "microservice_3" {
  source               = "../../../modules/k8s-microservice"
  name                 = "microservice-3"
  namespace            = module.security.namespace
  service_account_name = module.security.service_accounts["microservice-3"]
  image                = var.image
  command              = ["node", "dist/microservice-3/index.js"]
  port                 = 3003
  env = {
    MS3_PORT           = "3003"
    REDIS_PREFIX       = "ovhtest"
    REDIS_TLS_REQUIRED = "true"
  }
  env_from_secrets  = ["valkey"]
  image_pull_secret = "registry-pull"
  secret_revision   = var.secret_revision
  resources         = local.resources
  hpa_enabled       = false
  depends_on        = [kubernetes_manifest.valkey, kubernetes_manifest.registry_pull]
}

module "ingress" {
  source       = "../../../modules/k8s-ingress"
  namespace    = module.security.namespace
  host         = var.fqdn
  service_name = module.server.service_name
  service_port = 3000
}
