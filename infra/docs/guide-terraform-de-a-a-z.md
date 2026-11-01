# Guide Terraform OVHcloud de A à Z

Ce document explique deux choses :

1. comment concevoir une infrastructure Terraform structurée comme celle de ce dépôt ;
2. comment déployer concrètement le pilote OVHTest sur OVHcloud, dans le bon ordre et avec des contrôles à chaque étape.

Le but n'est pas de lancer une suite de commandes à l'aveugle. Chaque état Terraform est expliqué, ainsi que les valeurs qu'il reçoit, les ressources qu'il crée et les sorties à transmettre à l'étape suivante.

> **Attention au coût :** les ressources OVHcloud créées ici sont facturables. Le cluster, ses nœuds, la gateway, le Load Balancer, PostgreSQL, Valkey, le Registry, OKMS et Logs Data Platform peuvent tous générer des frais. Toujours lire le plan et vérifier l'estimation OVH avant un `apply`.

## 1. Ce que déploie ce projet

L'infrastructure finale contient :

- un vRack existant ou nouvellement commandé ;
- un réseau privé avec trois sous-réseaux : nœuds Kubernetes, Load Balancers et données ;
- une gateway de sortie pour les nœuds privés ;
- un cluster OVHcloud Managed Kubernetes Service en `GRA11` ;
- un node pool autoscalé de 1 à 2 nœuds `b3-8` ;
- PostgreSQL et Valkey managés sur le réseau privé ;
- un Container Registry privé ;
- un OVHcloud Key Management Service utilisé comme coffre de secrets ;
- Traefik, cert-manager et External Secrets Operator dans Kubernetes ;
- quatre composants Node.js et un Job de migration ;
- un enregistrement DNS et un certificat TLS Let's Encrypt ;
- une collecte de logs vers OVHcloud Logs Data Platform.

Le flux général est le suivant :

```mermaid
flowchart TD
    B[bootstrap : bucket de state] --> N[shared-network]
    N --> S[shared-services]
    N --> C[cluster MKS]
    S --> P[platform Kubernetes]
    C --> P
    P --> D[edge-dns]
    P --> A[applications]
    S --> A
    C --> O[observability]
    S --> O
    P --> O
```

Chaque boîte correspond à un dossier sous `infra/environments/pilot` et, sauf le bootstrap initial, à un state distant différent.

## 2. Pourquoi plusieurs states Terraform

### 2.1 Les notions Terraform à connaître

Terraform compare trois éléments :

- la **configuration** écrite dans les fichiers `.tf`, qui décrit le résultat souhaité ;
- le **state**, qui associe les adresses Terraform aux ressources cloud réelles ;
- l'**infrastructure réelle**, lue auprès des API OVHcloud et Kubernetes.

Les commandes principales ont chacune un rôle précis :

| Commande | Rôle | Modifie l'infrastructure |
| --- | --- | --- |
| `terraform init` | télécharge les providers/modules et configure le backend | non |
| `terraform fmt` | normalise la mise en forme du HCL | seulement les fichiers avec l'option d'écriture |
| `terraform validate` | vérifie la syntaxe et la cohérence statique | non |
| `terraform test` | exécute les tests `.tftest.hcl` | non ici, car les providers sont simulés |
| `terraform plan` | calcule les créations, modifications et suppressions | non |
| `terraform show PLAN` | affiche le contenu détaillé d'un plan enregistré | non |
| `terraform apply PLAN` | exécute exactement le plan relu | oui |
| `terraform output` | affiche les sorties du state | non |
| `terraform state list` | liste les ressources suivies par le state | non |

Un state n'est pas un fichier de configuration et ne doit jamais être modifié à la main. Il peut contenir des données sensibles même si aucun secret n'est déclaré en output ; son accès doit donc être aussi protégé que celui d'un coffre.

### 2.2 La séparation des states du projet

Un seul gros state serait plus simple au début, mais beaucoup plus risqué à exploiter. Ce projet sépare les ressources par cycle de vie :

| State | Responsabilité | Pourquoi l'isoler |
| --- | --- | --- |
| `bootstrap` | bucket S3 du state | le backend doit exister avant les autres states |
| `shared-network` | vRack, réseau, sous-réseaux, gateway | fondation stable et sensible |
| `shared-services` | PostgreSQL, Valkey, Registry, OKMS | ressources persistantes protégées contre la destruction |
| `cluster` | cluster MKS et node pool | peut évoluer sans recréer les bases |
| `platform` | Traefik, cert-manager, External Secrets | dépend du cluster, mais pas du code applicatif |
| `edge-dns` | enregistrement DNS public | dépend de l'IP du Load Balancer |
| `applications` | namespace, sécurité, migration, services et ingress | change à chaque nouvelle image |
| `observability` | stream LDP, subscriptions et Fluent Bit | peut être activé progressivement |

Cette séparation limite le rayon d'impact d'une erreur. Elle impose en contrepartie de copier explicitement les outputs d'un state dans les variables du suivant. Le projet n'utilise volontairement pas `terraform_remote_state` : les dépendances restent visibles et aucun secret ne transite automatiquement entre les states.

Voici la carte exacte des valeurs à transmettre :

| Producteur | Output ou valeur | Consommateur |
| --- | --- | --- |
| `bootstrap` | `bucket_name` | `infra/backend.hcl` |
| `shared-network` | `data_network_id`, `data_subnet_id` | `shared-services/terraform.tfvars` |
| `shared-network` | `node_network_id`, `nodes_subnet_id`, `load_balancers_subnet_id` | `cluster/terraform.tfvars` |
| `shared-services` | `okms_id`, `okms_rest_endpoint` | `platform/terraform.tfvars` |
| `shared-services` | endpoints PostgreSQL et Valkey | création manuelle des secrets |
| `shared-services` | `postgresql_cluster_id`, `valkey_cluster_id` | `observability/terraform.tfvars` |
| `cluster` | `cluster_id` | `observability/terraform.tfvars` sous le nom `kube_id` |
| Manager MKS | fichier kubeconfig | `platform`, `applications` et `observability` |
| Service Traefik | `EXTERNAL-IP` | `edge-dns/terraform.tfvars` |
| workflow GitHub | digest `registry/...@sha256:...` | `applications/versions.auto.tfvars` |
| Manager LDP | service name, rétention, hostname et token | tfvars d'observabilité et Secret Manager |

## 3. Comment créer un Terraform structuré comme celui-ci

Cette partie décrit la méthode de construction. Pour déployer directement le dépôt existant, passer à la section 4.

### 3.1 Définir l'architecture avant d'écrire du HCL

Commencer par lister :

- les ressources persistantes, par exemple les bases et le Registry ;
- les ressources remplaçables, par exemple les Deployments Kubernetes ;
- les dépendances : le cluster dépend du réseau, la plateforme dépend du cluster, le DNS dépend de l'IP Traefik ;
- les secrets nécessaires et l'endroit où ils seront créés ;
- les frontières de state correspondant aux différents cycles de vie.

Une règle utile : deux ressources qui ne sont pas administrées, modifiées ou détruites au même rythme ne devraient généralement pas partager le même root module.

### 3.2 Créer l'arborescence

Le modèle utilisé dans ce dépôt est :

```text
infra/
├── backend.hcl.example
├── modules/
│   ├── ovh-network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── ...
├── environments/
│   └── pilot/
│       ├── bootstrap/
│       ├── shared-network/
│       ├── shared-services/
│       ├── cluster/
│       ├── platform/
│       ├── edge-dns/
│       ├── applications/
│       └── observability/
└── tools/
    └── capabilities/
```

Il faut distinguer :

- un **module réutilisable** dans `infra/modules`, qui reçoit toutes ses informations par variables ;
- un **root module** dans `infra/environments/pilot`, qui configure les providers, le backend et appelle les modules avec les choix propres à l'environnement.

Par exemple, `modules/ovh-mks` sait créer un cluster générique. `environments/pilot/cluster` décide que le pilote utilise `GRA11`, Kubernetes `1.34`, le plan `free` et le flavor `b3-8`.

### 3.3 Construire chaque module avec quatre fichiers

Pour chaque module :

- `main.tf` contient les ressources ;
- `variables.tf` décrit les entrées, leurs types et leurs validations ;
- `outputs.tf` expose uniquement les identifiants nécessaires aux consommateurs ;
- `versions.tf` déclare les providers nécessaires et leurs contraintes.

Exemple minimal de module :

```hcl
# variables.tf
variable "name" {
  description = "Nom de la ressource."
  type        = string
}

# main.tf
resource "example_service" "this" {
  name = var.name
}

# outputs.tf
output "id" {
  value = example_service.this.id
}
```

Bonnes pratiques appliquées dans ce projet :

- typer toutes les variables ;
- utiliser des validations pour les valeurs à risque ;
- ne pas mettre de mot de passe dans une variable Terraform ;
- exposer des identifiants et endpoints, pas des credentials ;
- ajouter `prevent_destroy` aux ressources persistantes critiques ;
- fixer les versions Terraform, providers et charts Helm ;
- commiter les fichiers `.terraform.lock.hcl` produits par `terraform init` ;
- prévoir un test `terraform test` avec des providers simulés.

### 3.4 Construire un root module par state

Un root module contient au minimum :

```hcl
terraform {
  required_version = "= 1.17.1"

  backend "s3" {}

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "= 2.22.0"
    }
  }
}

provider "ovh" {
  endpoint = "ovh-eu"
}
```

Le bloc backend reste vide dans le code. Les informations locales et les credentials sont fournis lors de `terraform init` via `backend.hcl` et les variables d'environnement. Ainsi, aucun secret n'est commité.

Le root module appelle ensuite un module métier :

```hcl
module "network" {
  source = "../../../modules/ovh-network"

  service_name = var.service_name
  vrack_id     = var.vrack_id
  # ...
}
```

### 3.5 Séparer configuration et secrets

Les valeurs non secrètes vont dans un fichier `terraform.tfvars` local : régions, IDs de réseau, versions, CIDR ou noms de flavors.

Les secrets ne vont jamais dans :

- un fichier `.tf` ou `.tfvars` ;
- la ligne de commande `terraform plan -var=...` ;
- un output Terraform ;
- le state ;
- un secret Git commité.

Dans cette architecture, Terraform crée le coffre OKMS et les objets Kubernetes `ExternalSecret`, mais les mots de passe et tokens sont déposés manuellement dans OVHcloud Secret Manager. External Secrets Operator les copie ensuite vers Kubernetes.

### 3.6 Prévoir les protections Git

Le `.gitignore` doit au minimum exclure :

```gitignore
.terraform/
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
*.tflock
backend.hcl
backend.override.tf
infra/**/terraform.tfvars
kubeconfig*
*.pem
*.key
infra/**/secrets.auto.tfvars
infra/**/versions.auto.tfvars
```

Ne pas ignorer `.terraform.lock.hcl` : ce fichier verrouille les checksums et versions exactes des providers.

Avant chaque commit, contrôler les fichiers indexés :

```powershell
git status --short
git diff --cached
```

### 3.7 Ajouter validation, tests et CI

Pour chaque root module :

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
```

Les tests du dépôt utilisent `mock_provider`. Ils vérifient que la configuration peut produire un plan sans contacter OVHcloud ni Kubernetes. Ils ne remplacent pas un vrai plan : quotas, droits, compatibilités régionales et disponibilité commerciale ne peuvent être validés qu'avec le compte OVH cible.

La CI du projet valide le code et les tests, mais n'exécute aucun `terraform apply`. Un déploiement reste une action locale, relue et volontaire.

## 4. Préparer le poste de déploiement

### 4.1 Outils requis

Les versions fixées par le dépôt sont :

- Terraform `1.17.1` ;
- provider OVH `2.22.0` ;
- Helm `3.22.1` pour les contrôles manuels ;
- kubectl `1.34.1` ;
- Git ;
- Docker, uniquement pour tester ou construire localement ;
- Node.js 22, uniquement pour les tests applicatifs hors conteneur.

Depuis la racine du dépôt :

```powershell
infra/scripts/Test-Prerequisites.ps1
```

Vérifier aussi l'application avant de provisionner le cloud :

```powershell
npm ci
npm test
docker compose up --build
```

L'interface locale doit répondre sur `http://localhost:3000`.

### 4.2 Compte, domaine et quotas OVHcloud

Avant tout plan payant, vérifier dans le Manager OVHcloud :

- que le projet Public Cloud cible est le bon ;
- que la facturation est active ;
- que `GRA11` accepte au moins deux instances `b3-8` ;
- que le quota autorise une gateway et un Load Balancer ;
- que Kubernetes `1.34` et le plan Free sont disponibles ;
- que PostgreSQL, Valkey et leurs flavors choisis sont disponibles ;
- qu'un plan Container Registry est disponible en `GRA` ;
- que le vRack existe ou peut être commandé et rattaché au projet ;
- que la connexion privée entre les ressources `GRA11` et les services portant le libellé `GRA` est supportée ;
- que la zone DNS `minesave.fr` est administrable par le compte ;
- que la petite offre Logs Data Platform et une rétention de 7 jours sont disponibles.

Les versions et IDs présents dans les exemples sont des valeurs de référence. Les offres cloud évoluent : utiliser les valeurs réellement retournées pour le projet au moment du déploiement.

### 4.3 Credentials OVHcloud

Créer une application et un consumer key OVHcloud limités au projet et aux services nécessaires. Dans la session PowerShell utilisée pour Terraform :

```powershell
$env:OVH_ENDPOINT = "ovh-eu"
$env:OVH_APPLICATION_KEY = "..."
$env:OVH_APPLICATION_SECRET = "..."
$env:OVH_CONSUMER_KEY = "..."
```

Ne pas placer ces valeurs dans le dépôt. Les variables `$env:` ne valent que pour le processus courant et ses enfants ; ouvrir un nouveau terminal impose de les exporter à nouveau.

## 5. Inspecter les capacités sans créer de ressources

Le dossier `infra/tools/capabilities` ne contient que des data sources. Son `apply` lit les outputs, mais ne provisionne rien :

```powershell
terraform -chdir=infra/tools/capabilities init
terraform -chdir=infra/tools/capabilities fmt -check
terraform -chdir=infra/tools/capabilities validate
terraform -chdir=infra/tools/capabilities plan -out=capabilities.tfplan
terraform -chdir=infra/tools/capabilities apply capabilities.tfplan
terraform -chdir=infra/tools/capabilities output
```

Relever notamment :

- `gra11_flavors` pour confirmer `b3-8` ;
- `gra11_quota` pour la capacité CPU/RAM/instances ;
- `database_engines`, `database_plans` et `database_flavors` ;
- `registry_capabilities` pour l'ID du plan Registry.

Ne pas continuer si une ressource ou une région nécessaire n'est pas proposée.

## 6. Créer le backend distant

Terraform a besoin d'un bucket pour stocker ses states, mais ce bucket est lui-même créé par Terraform. Le bootstrap se fait donc d'abord avec un state local, puis ce state est migré vers S3.

### 6.1 Créer le bucket avec un state local

Le bucket par défaut est `ovhtest-tfstate-032692ab` en `GRA`, avec versioning et chiffrement serveur. Vérifier que le nom est adapté au projet ; un nom de bucket doit être unique.

```powershell
terraform -chdir=infra/environments/pilot/bootstrap init
terraform -chdir=infra/environments/pilot/bootstrap fmt -check
terraform -chdir=infra/environments/pilot/bootstrap validate
terraform -chdir=infra/environments/pilot/bootstrap test
terraform -chdir=infra/environments/pilot/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/environments/pilot/bootstrap show bootstrap.tfplan
```

Dans le plan, attendre exactement la création du bucket. Confirmer son coût, puis :

```powershell
infra/scripts/Confirm-Cost.ps1 -Lot "bootstrap" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=infra/environments/pilot/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/environments/pilot/bootstrap output
```

Le bucket est protégé par `prevent_destroy`.

### 6.2 Créer un utilisateur S3 dédié

Dans le Manager OVHcloud :

1. créer un utilisateur S3 réservé aux states Terraform ;
2. limiter ses droits au bucket de state ;
3. utiliser `infra/policies/tfstate-s3-user-policy.json` comme base de politique ;
4. récupérer l'Access Key et la Secret Key ;
5. les exporter dans le terminal :

```powershell
$env:AWS_ACCESS_KEY_ID = "..."
$env:AWS_SECRET_ACCESS_KEY = "..."
```

Ces credentials S3 sont distincts des credentials API OVH.

### 6.3 Configurer le backend

Créer le fichier local ignoré par Git :

```powershell
Copy-Item infra/backend.hcl.example infra/backend.hcl
```

Vérifier dans `infra/backend.hcl` :

- le nom exact du bucket ;
- la région `gra` ;
- l'endpoint S3 OVHcloud ;
- `use_lockfile = true` pour protéger les écritures concurrentes ;
- le chiffrement et le versioning déjà configurés côté bucket.

### 6.4 Migrer le state bootstrap

Le root module bootstrap n'a pas de backend S3 permanent, car le premier `init` doit rester local. Créer localement le fichier ignoré `infra/environments/pilot/bootstrap/backend.override.tf` :

```hcl
terraform {
  backend "s3" {}
}
```

Puis migrer :

```powershell
terraform -chdir=infra/environments/pilot/bootstrap init -migrate-state -backend-config=../../../backend.hcl -backend-config="key=pilot/bootstrap.tfstate"
terraform -chdir=infra/environments/pilot/bootstrap state list
terraform -chdir=infra/environments/pilot/bootstrap plan
```

Le dernier plan doit être vide. Conserver le state local de secours tant que la présence du state distant et son versioning n'ont pas été vérifiés.

## 7. Routine obligatoire pour chaque state

Pour tous les dossiers suivants, utiliser la même routine :

```powershell
terraform -chdir=CHEMIN init -backend-config=../../../backend.hcl -backend-config="key=pilot/NOM.tfstate"
terraform -chdir=CHEMIN fmt -check
terraform -chdir=CHEMIN validate
terraform -chdir=CHEMIN test
terraform -chdir=CHEMIN plan -out=NOM.tfplan
terraform -chdir=CHEMIN show NOM.tfplan
infra/scripts/Confirm-Cost.ps1 -Lot "NOM" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=CHEMIN apply NOM.tfplan
terraform -chdir=CHEMIN output
terraform -chdir=CHEMIN plan
```

Règles importantes :

- appliquer le fichier `.tfplan` relu, pas un nouvel `apply` sans argument ;
- ne pas réutiliser un plan après avoir modifié le code, les variables ou l'infrastructure ;
- arrêter immédiatement si le plan détruit ou remplace une ressource inattendue ;
- conserver une seule exécution Terraform à la fois sur une même clé de state ;
- attendre que le plan final affiche `No changes` avant de passer au lot suivant.

## 8. Déployer `shared-network`

### 8.1 Préparer les variables

```powershell
Copy-Item infra/environments/pilot/shared-network/terraform.tfvars.example infra/environments/pilot/shared-network/terraform.tfvars
```

Deux modes sont possibles.

Pour réutiliser un vRack :

```hcl
vrack_id     = "pn-xxxxxxxx"
create_vrack = false
vlan_id      = 40
```

Pour commander un vRack :

```hcl
vrack_id     = null
create_vrack = true
vlan_id      = 40
```

Ne jamais définir simultanément `vrack_id` et `create_vrack = true`. Un check Terraform bloque ce cas.

Le module crée les CIDR suivants :

- nœuds : `10.40.0.0/24` ;
- Load Balancers : `10.40.1.0/24` ;
- données : `10.40.2.0/24` ;
- pods Kubernetes : prévu plus tard en `10.42.0.0/16` ;
- services Kubernetes : prévu plus tard en `10.43.0.0/16`.

Ces plages ne doivent se chevaucher ni entre elles ni avec les réseaux reliés au vRack.

### 8.2 Initialiser, planifier et appliquer

```powershell
terraform -chdir=infra/environments/pilot/shared-network init -backend-config=../../../backend.hcl -backend-config="key=pilot/shared-network.tfstate"
terraform -chdir=infra/environments/pilot/shared-network validate
terraform -chdir=infra/environments/pilot/shared-network test
terraform -chdir=infra/environments/pilot/shared-network plan -out=shared-network.tfplan
terraform -chdir=infra/environments/pilot/shared-network show shared-network.tfplan
infra/scripts/Confirm-Cost.ps1 -Lot "shared-network" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=infra/environments/pilot/shared-network apply shared-network.tfplan
terraform -chdir=infra/environments/pilot/shared-network output
```

Copier les outputs suivants :

- `data_network_id` et `data_subnet_id` vers `shared-services/terraform.tfvars` ;
- `node_network_id`, `nodes_subnet_id` et `load_balancers_subnet_id` vers `cluster/terraform.tfvars`.

Vérifier dans le Manager que le réseau, les trois sous-réseaux et la gateway sont dans les régions attendues et rattachés au bon projet.

## 9. Déployer `shared-services`

### 9.1 Préparer les variables

```powershell
Copy-Item infra/environments/pilot/shared-services/terraform.tfvars.example infra/environments/pilot/shared-services/terraform.tfvars
```

Renseigner :

- `data_network_id` et `data_subnet_id` obtenus à l'étape précédente ;
- les versions PostgreSQL et Valkey réellement disponibles ;
- les plus petits flavors compatibles avec le pilote ;
- l'ID réel du plan Registry ;
- la région OKMS disponible.

Ne pas se contenter des versions de l'exemple. Elles doivent correspondre aux capabilities du projet le jour du déploiement.

### 9.2 Appliquer

```powershell
terraform -chdir=infra/environments/pilot/shared-services init -backend-config=../../../backend.hcl -backend-config="key=pilot/shared-services.tfstate"
terraform -chdir=infra/environments/pilot/shared-services validate
terraform -chdir=infra/environments/pilot/shared-services test
terraform -chdir=infra/environments/pilot/shared-services plan -out=shared-services.tfplan
terraform -chdir=infra/environments/pilot/shared-services show shared-services.tfplan
infra/scripts/Confirm-Cost.ps1 -Lot "shared-services" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=infra/environments/pilot/shared-services apply shared-services.tfplan
terraform -chdir=infra/environments/pilot/shared-services output
```

Ce state crée PostgreSQL, la base `ovhtest`, Valkey, le Registry et OKMS. PostgreSQL, Valkey, le Registry et OKMS sont protégés contre la destruction accidentelle.

Conserver :

- `postgresql_cluster_id` et `valkey_cluster_id` pour l'observabilité ;
- `postgresql_endpoints` et `valkey_endpoints` pour créer les secrets applicatifs ;
- `registry_url` pour la CI et l'image ;
- `okms_id` et `okms_rest_endpoint` pour la plateforme Kubernetes.

## 10. Créer les identités et secrets manuels

Cette étape est volontairement hors Terraform afin qu'aucun mot de passe ne se retrouve dans un plan ou un state.

### 10.1 PostgreSQL

Relever dans le Manager ou dans `terraform output postgresql_endpoints` l'hôte et le
port réellement exposés. Sur Public Cloud Databases, ce port est souvent un port
alloué comme `20184` et non `5432`.

L'onglet **Requêtes** du Manager sert à observer les requêtes ; ce n'est pas une
console SQL. Ouvrir une session `psql` TLS avec l'administrateur OVHcloud depuis un
poste autorisé, ou depuis un pod Kubernetes conforme à la politique PodSecurity.
Ajouter auparavant les CIDR réellement utilisés par les nœuds et les pods aux
restrictions IP du service PostgreSQL.

Depuis `psql` :

```sql
CREATE ROLE ovhtest_runtime LOGIN;
\password ovhtest_runtime
CREATE ROLE ovhtest_migration LOGIN;
\password ovhtest_migration

GRANT CONNECT ON DATABASE ovhtest TO ovhtest_runtime, ovhtest_migration;
GRANT USAGE, CREATE ON SCHEMA public TO ovhtest_migration;
GRANT USAGE ON SCHEMA public TO ovhtest_runtime;
REVOKE CREATE ON SCHEMA public FROM ovhtest_runtime;
```

Ne sélectionner le rôle OVHcloud `replication` ni pour `ovhtest_runtime` ni pour
`ovhtest_migration` : ce rôle ne donne pas les privilèges applicatifs. Les droits
utiles sont les `GRANT` SQL ci-dessus. Le Job de migration crée la table de test et
accorde ensuite au runtime uniquement `SELECT`, `INSERT` et l'usage de sa séquence.

Le mot de passe est celui saisi avec `\password`; OVHcloud ne permet pas de relire
un mot de passe existant. En cas de doute, le réinitialiser puis mettre à jour le
secret correspondant.

Créer dans Secret Manager :

- `pilot/ovhtest/database-runtime` avec `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_SSL` et `DB_SSL_REJECT_UNAUTHORIZED` ;
- `pilot/ovhtest/database-migration` avec les mêmes clés, mais le rôle de migration.

Valeurs : `DB_HOST` et `DB_PORT` doivent être copiés depuis l'endpoint OVHcloud,
`DB_NAME=ovhtest` et `DB_SSL=true`. Pour ce pilote, l'image Node.js n'a pas reconnu
la chaîne de certification présentée par le service : le manifeste force donc
`DB_SSL_REJECT_UNAUTHORIZED=false` tout en conservant le chiffrement TLS. En
production, monter explicitement l'autorité de certification OVHcloud et réactiver
la validation (`true`).

### 10.2 Valkey

Créer un utilisateur Valkey dédié, par exemple `ovhtest_runtime`. Il doit pouvoir
se connecter, lire/écrire les clés du préfixe applicatif et utiliser Pub/Sub sur
les canaux `ovhtest:*`. Une ACL minimale équivalente comprend `+ping`, les commandes
de lecture/écriture nécessaires, `+publish`, `+subscribe`, `+unsubscribe`,
`+psubscribe`, `+punsubscribe`, les clés `~ovhtest:*` et les canaux `&ovhtest:*`.
Dans le Manager, cela peut être présenté sous forme de rôle personnalisé ; le rôle
`replication` ne convient pas.

Stocker dans `pilot/ovhtest/valkey` :

```text
REDIS_URL=rediss://UTILISATEUR:MOT_DE_PASSE@HOTE:PORT
```

Le préfixe `rediss://` est obligatoire dans Kubernetes afin d'utiliser TLS.
Le schéma est exactement `rediss://` (pas `valkeys://`). Si l'utilisateur ou le mot
de passe contient un caractère réservé d'URL (`@`, `:`, `/`, `%`, etc.), encoder ce
composant en pourcentage avant de construire l'URL.

### 10.3 Registry

Créer deux identités distinctes :

- une identité **push** pour GitHub Actions ;
- une identité **pull** pour Kubernetes.

Dans GitHub, définir :

- secrets `OVH_REGISTRY_PUSH_USERNAME` et `OVH_REGISTRY_PUSH_PASSWORD` ;
- variables `OVH_REGISTRY_HOST` et `OVH_REGISTRY_REPOSITORY`.

Dans Secret Manager, créer `pilot/ovhtest/registry-pull` avec la propriété
`dockerconfigjson` (sans point initial) contenant un document Docker config JSON
complet. L'`ExternalSecret` copie cette propriété vers la clé Kubernetes
`.dockerconfigjson` (avec point) exigée par le type
`kubernetes.io/dockerconfigjson`. La valeur doit être un objet JSON, pas le JSON
échappé une seconde fois.

Ne pas poursuivre vers les applications avant que ces cinq secrets/identités ne soient prêts.

## 11. Déployer le cluster MKS

### 11.1 Préparer les variables

```powershell
Copy-Item infra/environments/pilot/cluster/terraform.tfvars.example infra/environments/pilot/cluster/terraform.tfvars
```

Renseigner les trois IDs obtenus depuis `shared-network`. Pour `admin_cidrs`, utiliser uniquement les adresses publiques fixes des administrateurs ou du VPN, idéalement en `/32` :

```hcl
admin_cidrs = ["203.0.113.10/32"]
```

Ne jamais ouvrir l'API Kubernetes à `0.0.0.0/0`.

### 11.2 Appliquer et récupérer le kubeconfig

```powershell
terraform -chdir=infra/environments/pilot/cluster init -backend-config=../../../backend.hcl -backend-config="key=pilot/cluster.tfstate"
terraform -chdir=infra/environments/pilot/cluster validate
terraform -chdir=infra/environments/pilot/cluster test
terraform -chdir=infra/environments/pilot/cluster plan -out=cluster.tfplan
terraform -chdir=infra/environments/pilot/cluster show cluster.tfplan
infra/scripts/Confirm-Cost.ps1 -Lot "cluster" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=infra/environments/pilot/cluster apply cluster.tfplan
terraform -chdir=infra/environments/pilot/cluster output
```

Attendre que le cluster et le node pool soient prêts. Depuis le Manager OVHcloud,
télécharger le kubeconfig et l'enregistrer sous
`.secrets/ovhtest-pilot-kubeconfig.yaml`. Le répertoire est ignoré par Git.

Tester l'accès :

```powershell
$env:KUBECONFIG = "$PWD\.secrets\ovhtest-pilot-kubeconfig.yaml"
kubectl cluster-info
kubectl get nodes -o wide
kubectl get namespaces
```

Les nœuds doivent être `Ready`. Si la connexion est refusée, vérifier d'abord l'adresse publique courante et `admin_cidrs`.

## 12. Déployer la plateforme Kubernetes

### 12.1 Préparer les variables

```powershell
Copy-Item infra/environments/pilot/platform/terraform.tfvars.example infra/environments/pilot/platform/terraform.tfvars
```

Renseigner :

```hcl
kubeconfig_path = "../../../../.secrets/ovhtest-pilot-kubeconfig.yaml"
okms_id         = "OUTPUT_OKMS_ID"
okms_server     = "OUTPUT_OKMS_REST_ENDPOINT"
```

Le chemin est résolu depuis le dossier `platform`, pas depuis le terminal.

### 12.2 Appliquer

```powershell
terraform -chdir=infra/environments/pilot/platform init -backend-config=../../../backend.hcl -backend-config="key=pilot/platform.tfstate"
terraform -chdir=infra/environments/pilot/platform validate
terraform -chdir=infra/environments/pilot/platform test
terraform -chdir=infra/environments/pilot/platform plan -out=platform.tfplan
terraform -chdir=infra/environments/pilot/platform show platform.tfplan
infra/scripts/Confirm-Cost.ps1 -Lot "platform" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=infra/environments/pilot/platform apply platform.tfplan
```

Ce state installe :

- Traefik avec un Service `LoadBalancer` ;
- cert-manager et ses CRD ;
- External Secrets Operator et ses CRD ;
- un `ClusterIssuer` Let's Encrypt ;
- un `ClusterSecretStore` OVHcloud.

### 12.3 Ajouter le certificat mTLS d'External Secrets

Créer dans OKMS un certificat d'accès ECDSA **sans CSR**. Le téléchargement initial
de la clé privée et le téléchargement ultérieur du certificat sont deux fichiers
différents :

- la clé commence par `-----BEGIN EC PRIVATE KEY-----` ou
  `-----BEGIN PRIVATE KEY-----` ;
- le certificat commence par `-----BEGIN CERTIFICATE-----` et peut contenir la
  chaîne complète, donc plusieurs blocs `CERTIFICATE` ;
- la clé et le premier certificat doivent former la même paire. Si `kubectl`
  signale `private key does not match public key`, retélécharger les deux éléments
  du même certificat d'accès.

Le certificat n'est disponible qu'après que le statut du certificat d'accès est
`Prêt`. Le bouton **Télécharger** de la fiche fournit alors le PEM public. Enregistrer
les fichiers localement sous `.secrets/client.crt` et `.secrets/client.key`, puis
créer le Secret directement dans Kubernetes :

```powershell
$env:KUBECONFIG = "$PWD\.secrets\ovhtest-pilot-kubeconfig.yaml"
kubectl -n external-secrets create secret tls ovhcloud-mtls --cert .\.secrets\client.crt --key .\.secrets\client.key --dry-run=client -o yaml | kubectl apply -f -
kubectl describe clustersecretstore ovhcloud
```

Attendre `Ready=True`. Les anciens événements `Secret not found` restent visibles
dans `describe` ; la condition courante et le dernier événement `Valid` font foi.
Ne jamais intégrer la clé privée à Terraform. Supprimer les copies locales devenues
inutiles selon la politique de sécurité de l'organisation.

### 12.4 Attendre l'IP du Load Balancer

```powershell
kubectl -n traefik get pods
kubectl -n traefik get service traefik --watch
```

Noter la valeur `EXTERNAL-IP` dès qu'elle apparaît, puis arrêter `--watch` avec `Ctrl+C`.

## 13. Configurer le DNS

### 13.1 Préparer et appliquer

```powershell
Copy-Item infra/environments/pilot/edge-dns/terraform.tfvars.example infra/environments/pilot/edge-dns/terraform.tfvars
```

Placer l'IP Traefik dans `load_balancer_ip`, puis :

```powershell
terraform -chdir=infra/environments/pilot/edge-dns init -backend-config=../../../backend.hcl -backend-config="key=pilot/edge-dns.tfstate"
terraform -chdir=infra/environments/pilot/edge-dns validate
terraform -chdir=infra/environments/pilot/edge-dns test
terraform -chdir=infra/environments/pilot/edge-dns plan -out=edge-dns.tfplan
terraform -chdir=infra/environments/pilot/edge-dns show edge-dns.tfplan
terraform -chdir=infra/environments/pilot/edge-dns apply edge-dns.tfplan
terraform -chdir=infra/environments/pilot/edge-dns output
```

Le résultat attendu est un enregistrement A `pilot.minesave.fr` avec un TTL de 300 secondes.

La chaîne de routage est la suivante :

```text
navigateur
  -> DNS A pilot.minesave.fr
  -> IP publique du Load Balancer OVHcloud
  -> Service Kubernetes traefik de type LoadBalancer
  -> Ingress dont l'hôte est pilot.minesave.fr
  -> Service ClusterIP server:3000
  -> pod server
```

L'adresse publique n'est donc ni l'IP d'un pod ni l'IP d'un nœud : OVHcloud la
provisionne lorsque Helm crée le Service Traefik de type `LoadBalancer`. Elle est
relevée avec `kubectl -n traefik get service traefik`, copiée dans
`edge-dns/terraform.tfvars`, puis `ovh_domain_zone_record.pilot` crée le lien DNS.
cert-manager utilise ensuite ce même routage pour le challenge HTTP-01 et le
certificat HTTPS.

Contrôler la propagation :

```powershell
Resolve-DnsName pilot.minesave.fr -Type A
```

La réponse doit correspondre à l'IP externe de Traefik.

## 14. Construire et publier l'image

Le workflow GitHub Actions `Build pilot image` :

1. installe les dépendances ;
2. exécute les tests ;
3. construit l'image Docker ;
4. la pousse dans le Registry avec le SHA Git ;
5. affiche son digest immuable dans le résumé du workflow.

Dans GitHub, lancer manuellement **Actions > Build pilot image > Run workflow**.

Copier la valeur complète :

```text
registry.gra.cloud.ovh.net/PROJET/ovhtest@sha256:...
```

Le digest, contrairement à un tag mutable, garantit que Kubernetes déploie exactement l'image relue.

## 15. Déployer les applications

### 15.1 Préparer les variables

```powershell
Copy-Item infra/environments/pilot/applications/terraform.tfvars.example infra/environments/pilot/applications/terraform.tfvars
```

Adapter le kubeconfig :

```hcl
kubeconfig_path = "../../../../.secrets/ovhtest-pilot-kubeconfig.yaml"
secret_revision = "1"
```

Créer le fichier local ignoré `infra/environments/pilot/applications/versions.auto.tfvars` :

```hcl
image = "registry.gra.cloud.ovh.net/PROJET/ovhtest@sha256:DIGEST_REEL"
```

### 15.2 Vérifier les secrets avant l'apply

```powershell
kubectl get clustersecretstore ovhcloud
```

Le store doit être prêt. Terraform va créer les `ExternalSecret`, puis le Job de migration attendra les secrets Kubernetes générés.

### 15.3 Appliquer

```powershell
terraform -chdir=infra/environments/pilot/applications init -backend-config=../../../backend.hcl -backend-config="key=pilot/applications.tfstate"
terraform -chdir=infra/environments/pilot/applications validate
terraform -chdir=infra/environments/pilot/applications test
terraform -chdir=infra/environments/pilot/applications plan -out=applications.tfplan
terraform -chdir=infra/environments/pilot/applications show applications.tfplan
terraform -chdir=infra/environments/pilot/applications apply applications.tfplan
```

L'apply effectue dans l'ordre :

1. création du namespace `ovhtest` et de ses règles de sécurité ;
2. création des `ExternalSecret` ;
3. exécution du Job de migration avec le rôle DDL ;
4. création des quatre Deployments ;
5. création des Services internes ;
6. création de l'Ingress Traefik.

### 15.4 Contrôler le rollout

```powershell
kubectl -n ovhtest get externalsecrets
kubectl -n ovhtest get jobs
kubectl -n ovhtest get deployments,pods,services,ingress
kubectl -n ovhtest rollout status deployment/server
kubectl -n ovhtest rollout status deployment/microservice-1
kubectl -n ovhtest rollout status deployment/microservice-2
kubectl -n ovhtest rollout status deployment/microservice-3
```

Si le Job de migration échoue, lire ses logs sans afficher les Secrets :

```powershell
kubectl -n ovhtest get pods -l app.kubernetes.io/name=database-migration
kubectl -n ovhtest logs job/NOM_EXACT_DU_JOB
```

Ne pas utiliser `kubectl describe secret` ou une sortie JSON/YAML des Secrets dans un terminal enregistré.

## 16. Vérifier le HTTPS et l'application

Après propagation DNS, cert-manager traite le challenge HTTP-01 :

```powershell
kubectl -n ovhtest get certificate,certificaterequest,challenge,order
kubectl -n ovhtest get ingress
```

Le certificat `pilot-minesave-fr-tls` doit devenir prêt.

Tester ensuite :

```powershell
curl.exe -I http://pilot.minesave.fr
curl.exe -I https://pilot.minesave.fr
curl.exe https://pilot.minesave.fr/api/health
curl.exe https://pilot.minesave.fr/api/live
curl.exe https://pilot.minesave.fr/api/status
```

Résultats attendus :

- HTTP redirige vers HTTPS ;
- le certificat est valide pour `pilot.minesave.fr` ;
- `/api/health` et `/api/live` répondent avec succès ;
- `/api/status` confirme les dépendances applicatives ;
- l'interface et le WebSocket fonctionnent dans le navigateur.

## 17. Déployer l'observabilité

### 17.1 Préparer LDP et son secret

Activer la plus petite offre Logs Data Platform et choisir une rétention de 7 jours. Créer dans Secret Manager `pilot/shared/ldp` avec une propriété `token` contenant le write token LDP.

Copier le fichier d'exemple :

```powershell
Copy-Item infra/environments/pilot/observability/terraform.tfvars.example infra/environments/pilot/observability/terraform.tfvars
```

Renseigner :

- le chemin du kubeconfig ;
- le service name LDP ;
- l'ID de rétention ;
- le hostname LDP exact ;
- `cluster_id` obtenu depuis le state `cluster` comme `kube_id` ;
- les IDs PostgreSQL et Valkey obtenus depuis `shared-services`.

Laisser d'abord :

```hcl
enable_mks_audit_logs = false
enable_database_logs  = false
```

Activer ces options seulement après avoir confirmé les `kind` acceptés par l'API OVH.

### 17.2 Appliquer et contrôler

```powershell
terraform -chdir=infra/environments/pilot/observability init -backend-config=../../../backend.hcl -backend-config="key=pilot/observability.tfstate"
terraform -chdir=infra/environments/pilot/observability validate
terraform -chdir=infra/environments/pilot/observability test
terraform -chdir=infra/environments/pilot/observability plan -out=observability.tfplan
terraform -chdir=infra/environments/pilot/observability show observability.tfplan
infra/scripts/Confirm-Cost.ps1 -Lot "observability" -EstimationMensuelle "VALEUR_DU_MANAGER"
terraform -chdir=infra/environments/pilot/observability apply observability.tfplan
```

Vérifier :

```powershell
kubectl -n logging get externalsecret,pods
kubectl -n logging get daemonset
```

Chaque nœud doit exécuter un pod Fluent Bit. Les logs des quatre composants doivent ensuite apparaître dans le stream `ovhtest-pilot` de LDP.

## 18. Validation finale

### 18.1 Vérifier l'absence de dérive Terraform

Exécuter un plan sans `-out` dans chacun des huit dossiers. Tous doivent être vides :

```powershell
terraform -chdir=infra/environments/pilot/bootstrap plan
terraform -chdir=infra/environments/pilot/shared-network plan
terraform -chdir=infra/environments/pilot/shared-services plan
terraform -chdir=infra/environments/pilot/cluster plan
terraform -chdir=infra/environments/pilot/platform plan
terraform -chdir=infra/environments/pilot/edge-dns plan
terraform -chdir=infra/environments/pilot/applications plan
terraform -chdir=infra/environments/pilot/observability plan
```

### 18.2 Checklist fonctionnelle et sécurité

- [ ] les huit states sont distants, versionnés et verrouillés ;
- [ ] aucun secret n'apparaît dans Git, un plan, un state ou un log ;
- [ ] l'API Kubernetes n'accepte que les CIDR administrateurs ;
- [ ] PostgreSQL et Valkey ne sont pas exposés à Internet ;
- [ ] les connexions PostgreSQL et Valkey utilisent TLS ;
- [ ] il n'existe qu'un Load Balancer Octavia, celui de Traefik ;
- [ ] le DNS pointe vers l'IP de Traefik ;
- [ ] HTTP redirige vers HTTPS et le certificat est valide ;
- [ ] le Job de migration est terminé avec succès ;
- [ ] les quatre Deployments sont disponibles ;
- [ ] les health checks, l'UI, l'API et le WebSocket fonctionnent ;
- [ ] les logs arrivent dans LDP ;
- [ ] un rollback vers le digest précédent a été testé ;
- [ ] une rotation de secret a été testée sans exposer sa valeur.

## 19. Déployer une nouvelle version

Pour une nouvelle release applicative :

1. lancer le workflow `Build pilot image` ;
2. récupérer le nouveau digest ;
3. remplacer uniquement `image` dans `versions.auto.tfvars` ;
4. planifier et relire le state `applications` ;
5. appliquer le plan ;
6. contrôler le Job de migration et les quatre rollouts ;
7. tester les endpoints publics.

Pour un rollback, remettre le digest précédent et répéter exactement le même processus. Les migrations doivent rester rétrocompatibles.

Pour forcer un redémarrage après rotation d'un secret, incrémenter `secret_revision`, produire un plan et l'appliquer. Cette valeur modifie une annotation du template de pod et déclenche un rollout contrôlé.

## 20. Dépannage

### `terraform init` ne trouve pas le backend

Vérifier :

- que `infra/backend.hcl` existe ;
- que le chemin relatif est bien `../../../backend.hcl` depuis le root module ;
- que les deux variables AWS sont exportées ;
- que l'endpoint S3 et le nom du bucket sont exacts.

### Terraform signale un verrou

Ne jamais supprimer immédiatement le fichier de lock. Vérifier qu'aucun autre plan/apply ne tourne. Pour un verrou réellement orphelin, sauvegarder d'abord le state versionné, puis utiliser :

```powershell
terraform -chdir=CHEMIN force-unlock ID_DU_LOCK
```

### Le cluster est inaccessible

Vérifier :

- que l'IP publique actuelle appartient à `admin_cidrs` ;
- que le kubeconfig correspond au bon cluster ;
- que le cluster et le node pool sont prêts ;
- que le fichier n'a pas expiré ou été remplacé.

### Un ExternalSecret n'est pas prêt

```powershell
kubectl get clustersecretstore ovhcloud
kubectl -n NOM_NAMESPACE get externalsecret
kubectl -n NOM_NAMESPACE describe externalsecret NOM
```

Contrôler le certificat mTLS, le chemin exact du secret distant et le nom de sa propriété. Ne pas afficher la valeur du Secret Kubernetes.

### L'image ne peut pas être téléchargée

Vérifier :

- que le digest existe dans le Registry ;
- que la propriété distante `dockerconfigjson` existe et contient un JSON Docker
  complet ; l'`ExternalSecret` la transforme en clé Kubernetes `.dockerconfigjson` ;
- que l'identité pull a le droit de lire le repository ;
- que l'`ExternalSecret` `registry-pull` est prêt.

### Le certificat TLS reste en attente

Vérifier dans cet ordre :

1. le DNS public ;
2. l'IP externe de Traefik ;
3. l'Ingress et son annotation `cluster-issuer` ;
4. les objets `Certificate`, `Order` et `Challenge` ;
5. la NetworkPolicy autorisant Traefik vers le solver HTTP-01.

### L'apply applicatif attend le Job de migration

Le timeout est de dix minutes. Vérifier le pod du Job, la résolution DNS privée, la
connectivité au `DB_PORT` réel de l'endpoint, le secret de migration et le certificat
TLS PostgreSQL. Corriger la cause, produire un nouveau plan, puis réappliquer ; ne
pas contourner la migration.

Ne pas se fier au port standard `5432` dans ce diagnostic : tester le `DB_PORT`
réel du secret (par exemple `20184`). Les erreurs ont des significations distinctes :

- `Connection timed out` : routage, restriction IP OVHcloud, NetworkPolicy ou CIDR
  incorrect ;
- `no password supplied` : le réseau fonctionne, mais le client n'a pas reçu le
  mot de passe ;
- `password authentication failed` : utilisateur/mot de passe incorrect ;
- `permission denied` : la connexion fonctionne, mais les `GRANT` SQL manquent ;
- erreur de chaîne X.509 : TLS fonctionne, mais l'autorité n'est pas approuvée par
  l'image cliente.

### Terraform reste sur `Still creating`

Terraform attend la réussite du Job et la disponibilité des Deployments. Ne pas
attendre dix minutes à l'aveugle : ouvrir un second terminal et exécuter :

```powershell
$env:KUBECONFIG = "$PWD\.secrets\ovhtest-pilot-kubeconfig.yaml"
kubectl -n ovhtest get pods
kubectl -n ovhtest get events --sort-by=.lastTimestamp | Select-Object -Last 30
kubectl -n ovhtest logs job/database-migration-9173b81f0d --tail=100
kubectl -n ovhtest logs deployment/server --tail=100
kubectl -n ovhtest logs deployment/microservice-2 --tail=100
kubectl -n ovhtest logs deployment/microservice-3 --tail=100
```

Adapter le nom du Job obtenu par `kubectl -n ovhtest get jobs`. Après correction,
ne pas réutiliser un ancien fichier `.tfplan` : recréer le plan. Un Job ayant atteint
`BackoffLimitExceeded` est immuable ; supprimer ce Job échoué avant le nouvel apply
si Terraform ne peut pas le remplacer.

### `kubectl` tente `localhost:8080`

La variable `KUBECONFIG` n'est définie que dans le terminal PowerShell courant.
La redéfinir dans chaque nouvelle session :

```powershell
$env:KUBECONFIG = "$PWD\.secrets\ovhtest-pilot-kubeconfig.yaml"
kubectl config current-context
kubectl cluster-info
```

Une erreur vers `http://localhost:8080` ne vient donc pas du cluster : elle signifie
que `kubectl` n'a chargé aucun kubeconfig valide.

### PostgreSQL ou Valkey reste inaccessible depuis les pods

Vérifier les trois couches séparément :

1. l'endpoint privé résout vers le subnet data (`10.40.2.0/24`) ;
2. la NetworkPolicy autorise les ports OVHcloud réellement attribués (`20184` et
   `20185` dans ce pilote), pas seulement `5432` et `6379` ;
3. les restrictions IP OVHcloud couvrent le CIDR des nœuds et le CIDR réellement
   observé sur les pods (`kubectl -n ovhtest get pods -o wide`).

Le namespace applique PodSecurity `restricted`. Un pod de diagnostic improvisé est
refusé s'il n'a pas `runAsNonRoot=true`, `allowPrivilegeEscalation=false`,
`capabilities.drop=["ALL"]` et `seccompProfile.type=RuntimeDefault`. Réutiliser ces
champs dans tout manifeste de diagnostic, puis supprimer le pod après le test.

### Valkey répond `NOPERM ... subscribe`

La connexion et le mot de passe sont valides, mais l'ACL n'autorise pas Pub/Sub.
Ajouter au rôle de `ovhtest_runtime` les commandes `PUBLISH`, `SUBSCRIBE`,
`UNSUBSCRIBE`, `PSUBSCRIBE`, `PUNSUBSCRIBE` et le motif de canaux `&ovhtest:*`, puis
redémarrer `server` et `microservice-3`. Le droit sur les clés `~ovhtest:*` ne donne
pas automatiquement le droit sur les canaux.

### Le serveur écoute sur un port de type `tcp://...`

Kubernetes injecte des variables de service comme `SERVER_PORT`. Elles peuvent
entrer en collision avec les variables applicatives. Le module désactive désormais
`enable_service_links` et le serveur reçoit explicitement `SERVER_PORT=3000`.
Conserver des noms d'environnement applicatifs non ambigus pour les futurs services.

### Un service reste `STARTING` alors que son pod est prêt

Les statuts du tableau de bord sont conservés en mémoire par `server`. Un redémarrage
du serveur efface les statuts déjà envoyés. Les microservices doivent renvoyer leur
état périodiquement ; `microservice-2` possède un heartbeat. Tant que l'image incluant
ce correctif n'est pas construite et déployée, redémarrer le microservice après le
serveur masque seulement la course de démarrage.

Pour un redémarrage contrôlé de tous les Deployments :

```powershell
kubectl -n ovhtest rollout restart deployment
kubectl -n ovhtest rollout status deployment/server --timeout=5m
kubectl -n ovhtest get pods -w
```

Le rolling restart est volontairement transparent : le Service et l'Ingress restent
stables pendant que Kubernetes remplace les pods. Arrêter `-w` avec `Ctrl+C` ; ce
n'est pas un blocage.

## 21. Destruction et fin de pilote

Cette procédure est réservée au cas où le projet Public Cloud est dédié au pilote.
Pour le projet `032692ab7ad4437f9140d11b371eb451`, cette exclusivité a été confirmée.
La suppression est irréversible : sauvegarder auparavant toute donnée ou tout state
qui doit servir à un audit.

Les protections ont deux niveaux : `prevent_destroy` dans Terraform et
`deletion_protection` côté OVHcloud. La modification de fin de pilote retire les
`prevent_destroy` de PostgreSQL, Valkey, Registry et OKMS, et fixe les deux
`deletion_protection` à `false`. Un apply normal de `shared-services` doit d'abord
propager cette désactivation ; le plan de destruction vient seulement ensuite.

### 21.1 Préparer la session et sauvegarder les states

```powershell
Set-Location C:\Users\match\Documents\code\OVHTest
$env:KUBECONFIG = "$PWD\.secrets\ovhtest-pilot-kubeconfig.yaml"
kubectl config current-context

$backup = ".secrets\state-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $backup | Out-Null
$states = @('bootstrap','shared-network','shared-services','cluster','platform','edge-dns','applications','observability')
foreach ($state in $states) {
  terraform "-chdir=infra/environments/pilot/$state" init -reconfigure "-backend-config=../../../backend.hcl" "-backend-config=key=pilot/$state.tfstate"
  terraform "-chdir=infra/environments/pilot/$state" state pull |
    Set-Content -Encoding utf8 "$backup/$state.tfstate"
}
```

Ne jamais publier ce dossier : un state peut contenir des données sensibles.

### 21.2 Détruire les states dans l'ordre

Chaque paire `plan -destroy` / `apply` est volontairement séparée afin de relire le
plan. Ne continuer que si le plan ne vise que le lot nommé.

```powershell
terraform "-chdir=infra/environments/pilot/edge-dns" plan -destroy "-out=edge-dns-destroy.tfplan"
terraform "-chdir=infra/environments/pilot/edge-dns" apply "edge-dns-destroy.tfplan"

$obsDir = "infra/environments/pilot/observability"
$obsResources = @(terraform "-chdir=$obsDir" state list 2>$null)

if ($LASTEXITCODE -ne 0 -or $obsResources.Count -eq 0) {
  Write-Host "State observability absent ou vide : aucun destroy nécessaire"
} else {
  $obsState = terraform "-chdir=$obsDir" state pull | ConvertFrom-Json
  $stream = $obsState.resources | Where-Object type -eq "ovh_dbaas_logs_output_graylog_stream" | Select-Object -First 1
  $fluentBit = $obsState.resources | Where-Object type -eq "helm_release" | Select-Object -First 1
  if (-not $stream -or -not $fluentBit) { throw "State observability incomplet" }

  $ldpService = [string]$stream.instances[0].attributes.service_name
  $retentionId = [string]$stream.instances[0].attributes.retention_id
  $helmValues = [string]$fluentBit.instances[0].attributes.values[0]
  $hostMatch = [regex]::Match($helmValues, '(?m)^\s*Host\s+([A-Za-z0-9.-]+)\s*$')
  if (-not $hostMatch.Success) { throw "Impossible de retrouver ldp_host dans le state Helm" }

  $obsVars = @(
    "-var=kubeconfig_path=$env:KUBECONFIG",
    "-var=ldp_service_name=$ldpService",
    "-var=retention_id=$retentionId",
    "-var=ldp_host=$($hostMatch.Groups[1].Value)",
    "-var=kube_id=$(terraform '-chdir=infra/environments/pilot/cluster' output -raw cluster_id)",
    "-var=postgresql_cluster_id=$(terraform '-chdir=infra/environments/pilot/shared-services' output -raw postgresql_cluster_id)",
    "-var=valkey_cluster_id=$(terraform '-chdir=infra/environments/pilot/shared-services' output -raw valkey_cluster_id)"
  )

  terraform "-chdir=$obsDir" plan -destroy "-out=observability-destroy.tfplan" @obsVars
  terraform "-chdir=$obsDir" show "observability-destroy.tfplan"
  terraform "-chdir=$obsDir" apply "observability-destroy.tfplan"
}

terraform "-chdir=infra/environments/pilot/applications" plan -destroy "-out=applications-destroy.tfplan"
terraform "-chdir=infra/environments/pilot/applications" apply "applications-destroy.tfplan"

terraform "-chdir=infra/environments/pilot/platform" plan -destroy "-out=platform-destroy.tfplan"
terraform "-chdir=infra/environments/pilot/platform" apply "platform-destroy.tfplan"
```

À ce point, vérifier dans le Manager que le Load Balancer associé à l'IP publique a
disparu. Le Service Traefik doit être supprimé avant le cluster afin que le cloud
controller puisse libérer proprement le Load Balancer.

```powershell
kubectl get service -A
terraform "-chdir=infra/environments/pilot/cluster" plan -destroy "-out=cluster-destroy.tfplan"
terraform "-chdir=infra/environments/pilot/cluster" apply "cluster-destroy.tfplan"
```

Après la destruction du cluster, `kubectl` doit échouer : c'est attendu.

Propager ensuite la levée de protection des services, puis les détruire :

```powershell
terraform "-chdir=infra/environments/pilot/shared-services" plan "-out=shared-services-unprotect.tfplan"
terraform "-chdir=infra/environments/pilot/shared-services" apply "shared-services-unprotect.tfplan"
terraform "-chdir=infra/environments/pilot/shared-services" plan -destroy "-out=shared-services-destroy.tfplan"
terraform "-chdir=infra/environments/pilot/shared-services" apply "shared-services-destroy.tfplan"
```

Avant de détruire le réseau, supprimer dans le Manager tout service créé hors state
qui l'utilise encore, notamment un éventuel Valkey dupliqué lors d'un apply interrompu.
Attendre sa disparition complète, puis :

```powershell
terraform "-chdir=infra/environments/pilot/shared-network" plan -destroy "-out=shared-network-destroy.tfplan"
terraform "-chdir=infra/environments/pilot/shared-network" apply "shared-network-destroy.tfplan"
```

Si `shared-services` échoue sur OKMS avec un `403` visant
`/me/notification/email/history`, le provider ne peut pas lire l'e-mail contenant
le jeton de confirmation de résiliation. La solution la moins permissive consiste à
supprimer OKMS depuis le Manager, confirmer l'e-mail, attendre sa disparition, puis
retirer **uniquement après cette vérification** son adresse du state :

```powershell
terraform "-chdir=infra/environments/pilot/shared-services" state list
terraform "-chdir=infra/environments/pilot/shared-services" state rm "module.secrets.ovh_okms.this"
terraform "-chdir=infra/environments/pilot/shared-services" state list
```

L'autre possibilité est de créer un consumer key temporaire autorisant les routes
de résiliation documentées par le provider : lecture de
`/me/notification/email/history` et de ses éléments, lecture de `/services`, puis
`POST /services/*/terminate` et `POST /services/*/terminate/confirm`. Ces routes sont
globales au compte ; révoquer immédiatement ce consumer key après la destruction.

Si le Manager refuse d'abord la suppression d'OKMS, supprimer dans OKMS les
certificats d'accès et les secrets encore présents, puis recommencer. Si
`shared-network` échoue avec un port ou un subnet encore utilisé, ne forcer aucune suppression :
chercher dans le Manager le PostgreSQL, Valkey, Load Balancer, gateway ou port
OpenStack orphelin, le supprimer, attendre la fin de l'opération, puis recréer le
plan. OVHcloud bloque volontairement la suppression d'un réseau encore attaché à
un service de base de données.

Le vRack `pn-1364156` n'est pas détruit : `create_vrack=false` indique qu'il existait
avant le pilote. Vérifier qu'il n'entraîne pas une facturation propre et le conserver
s'il sert ailleurs.

### 21.3 Supprimer les ressources hors state et fermer le projet

Dans le Manager OVHcloud :

1. vérifier qu'il ne reste ni cluster, node pool, Load Balancer, Floating/Additional
   IP, Registry, PostgreSQL, Valkey, Object Storage ni ressource réseau du pilote ;
2. supprimer l'éventuel Valkey dupliqué ;
3. résilier le service Logs Data Platform activé manuellement s'il était dédié ;
4. vérifier la disparition d'OKMS, qui est un service de compte et non une simple
   ressource Kubernetes ;
5. ouvrir **Public Cloud > Project settings > Delete project**, supprimer le projet
   `032692ab7ad4437f9140d11b371eb451` et confirmer l'e-mail OVHcloud.

Ne pas exécuter `terraform destroy` sur `bootstrap` tant que les autres states sont
encore distants : ce lot contient le bucket qui les héberge. Puisque le projet est
entièrement supprimé, sa fermeture supprime finalement ce bucket et les states. La
sauvegarde locale précédente est la trace d'audit.

Le domaine `minesave.fr` et le vRack préexistant ne font pas partie du projet et ne
sont donc pas résiliés. Le record A `pilot` est supprimé par `edge-dns`, mais le
renouvellement du domaine continue tant qu'il n'est pas résilié séparément.

## 22. Fichiers de référence

- `infra/README.md` : résumé opératoire ;
- `infra/docs/manual-bootstrap.md` : schéma exact des secrets et identités ;
- `infra/docs/runbook.md` : rotation, rollback, restauration et incident Terraform ;
- `infra/backend.hcl.example` : configuration S3 du backend ;
- `infra/policies/tfstate-s3-user-policy.json` : politique de l'utilisateur S3 ;
- `infra/scripts/Test-Prerequisites.ps1` : contrôle des outils ;
- `infra/scripts/Confirm-Cost.ps1` : confirmation humaine du coût ;
- `.github/workflows/ci.yml` : validations automatiques ;
- `.github/workflows/build-pilot-image.yml` : construction de l'image immuable.
