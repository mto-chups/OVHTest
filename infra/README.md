# Pilote OVHcloud — guide opératoire

Cette arborescence déploie le projet Public Cloud `032692ab7ad4437f9140d11b371eb451` par états indépendants. Les commandes ci-dessous sont volontairement locales : la CI ne possède aucun droit Terraform.

Pour comprendre comment reconstruire cette architecture et suivre un déploiement commenté de bout en bout, consulter le [guide Terraform OVHcloud de A à Z](docs/guide-terraform-de-a-a-z.md).

## 0. Préparer le poste et confirmer les capacités

Versions attendues : Terraform `1.17.1`, Helm `3.22.1` et kubectl `1.34.1`. Sous Windows, les binaires téléchargés localement dans `.tools/` sont utilisés si l'installation système n'est pas possible (ce dossier reste ignoré par Git).

```powershell
infra/scripts/Test-Prerequisites.ps1
```

Dans le Manager OVHcloud, vérifier avant tout plan payant :

1. facturation et quotas actifs en `GRA11` ; au moins deux instances `b3-8`, réseau privé, une gateway et un load balancer ;
2. Kubernetes `1.34` et plan Free disponibles ;
3. versions stables PostgreSQL/Valkey et plus petits flavors Essential disponibles en région `GRA` ;
4. plan Registry disponible ;
5. vRack existant attachable au projet et connectivité privée `GRA11` ↔ `GRA` ;
6. activation de la plus petite offre Logs Data Platform, rétention 7 jours.

Les quotas, flavors, capacités DB et plans Registry exposés par l'API peuvent être interrogés en lecture seule :

```powershell
terraform -chdir=infra/tools/capabilities init
terraform -chdir=infra/tools/capabilities plan -out capabilities.tfplan
terraform -chdir=infra/tools/capabilities apply capabilities.tfplan
terraform -chdir=infra/tools/capabilities output
```

Ce dossier d'inspection ne possède aucun resource block et ne provisionne rien. Les versions Kubernetes proposées et la compatibilité vRack inter-régions restent à confirmer dans le Manager/API avant de figer les tfvars.

Reporter les valeurs réellement proposées dans les `terraform.tfvars` locaux. Ne jamais commiter ces fichiers s'ils contiennent des informations d'administration. Afficher les estimations du Manager avec `infra/scripts/Confirm-Cost.ps1`; chaque `apply` exige de saisir `APPROUVE`.

## 1. Identifiants OVH et backend

Exporter hors dépôt `OVH_ENDPOINT=ovh-eu`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET` et `OVH_CONSUMER_KEY`. Créer le bucket :

```powershell
cd infra/environments/pilot/bootstrap
terraform init
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Créer ensuite dans le Manager un compte S3 dédié, limité à `ovhtest-tfstate-032692ab`, puis exporter `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY`. Copier `infra/backend.hcl.example` vers `infra/backend.hcl` et renseigner l'endpoint S3 GRA. Pour migrer le state bootstrap, créer localement `bootstrap/backend.override.tf` avec le bloc backend S3, puis :

```powershell
terraform init -migrate-state -backend-config=../../../backend.hcl -backend-config="key=pilot/bootstrap.tfstate"
```

Tester le verrouillage en lançant deux plans simultanés : le second doit attendre ou échouer sur `pilot/bootstrap.tfstate.tflock`. Tester aussi la récupération d'une version antérieure depuis le versioning S3.

## 2. Ordre des états

Pour chaque répertoire, copier `terraform.tfvars.example` vers `terraform.tfvars`, renseigner les valeurs non secrètes, puis exécuter :

```powershell
terraform init -backend-config=../../../backend.hcl -backend-config="key=pilot/NOM.tfstate"
terraform fmt -check -recursive
terraform validate
terraform plan -out NOM.tfplan
# Relire intégralement le plan et confirmer son coût dans le Manager.
terraform apply NOM.tfplan
```

Ordre : `shared-network`, `shared-services`, `cluster`, `platform`, `edge-dns`, `applications`, `observability`. Les outputs inter-états se copient explicitement dans les tfvars suivants ; aucun secret ne transite par un state.

## 3. Étapes manuelles de sécurité

Après `shared-services` :

- créer les rôles PostgreSQL migration/runtime, l'utilisateur Valkey et les identités Registry push/pull ;
- déposer directement leurs valeurs dans OVHcloud Secret Manager sous `pilot/ovhtest/database-runtime`, `pilot/ovhtest/database-migration`, `pilot/ovhtest/valkey`, `pilot/ovhtest/registry-pull`, puis le token LDP sous `pilot/shared/ldp` ;
- ne jamais passer ces valeurs à Terraform.

Après `cluster`, télécharger le kubeconfig depuis l'onglet **Service** du cluster MKS dans le Manager et l'enregistrer sous `kubeconfig-pilot.yaml` (ignoré par Git). Ne pas l'exposer en output Terraform.

Restreindre l'API Kubernetes aux CIDR administrateurs avant toute charge. Après le premier apply `platform`, créer manuellement le Secret Kubernetes `external-secrets/ovhcloud-mtls` contenant `cert.pem` et `key.pem`; le certificat privé ne doit jamais entrer dans Terraform. Vérifier ensuite que le `ClusterSecretStore` passe à `Ready=True`.

Les commandes et le schéma précis des cinq secrets sont décrits dans [docs/manual-bootstrap.md](docs/manual-bootstrap.md).

## 4. DNS, image et application

Attendre l'IP externe du Service Traefik, la reporter dans `edge-dns/load_balancer_ip`, puis appliquer `edge-dns`. Le ClusterIssuer HTTP-01 émettra le certificat de `pilot.minesave.fr` après propagation DNS.

Le workflow `Build pilot image` construit et pousse une image taguée par SHA. Reporter son digest `sha256:…` dans `applications/versions.auto.tfvars` sous la forme `registry/path@sha256:…`, planifier et appliquer localement. Le Job de migration s'exécute avec le rôle DDL ; les Deployments utilisent uniquement le rôle runtime.

## 5. Critères avant clôture

- `terraform plan` vide pour chacun des huit états ;
- un seul load balancer Octavia, créé par le Service Traefik ;
- PostgreSQL/Valkey non joignables depuis Internet mais joignables en TLS depuis les pods ;
- DNS, certificat public et redirection HTTP vers HTTPS valides ;
- quatre health checks, UI/API/WebSocket, migration, PostgreSQL et Valkey validés ;
- secrets absents des plans, states et logs ; rotation ESO testée ;
- logs des quatre composants visibles dans LDP ;
- rollout par digest et rollback vers le digest précédent testés.

Les procédures de sécurité et restauration sont détaillées dans [docs/runbook.md](docs/runbook.md).
