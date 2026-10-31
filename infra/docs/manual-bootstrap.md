# Bootstrap manuel des identités et secrets

Terraform ne reçoit volontairement aucun mot de passe, token, kubeconfig ou certificat privé. Effectuer ces opérations après `shared-services` et avant `applications`.

## PostgreSQL

Depuis une session `psql` TLS ouverte avec l'administrateur fourni par OVHcloud :

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

`\password` demande le mot de passe sans l'inscrire dans l'historique SQL. Le Job de migration accorde ensuite au runtime uniquement `SELECT`, `INSERT` et l'usage de la séquence sur `deployment_checks`; il ne lui accorde aucun DDL.

Créer dans Secret Manager deux secrets JSON :

- `pilot/ovhtest/database-runtime` avec `DB_HOST`, `DB_PORT`=`5432`, `DB_USER`=`ovhtest_runtime`, `DB_PASSWORD`, `DB_NAME`=`ovhtest`, `DB_SSL`=`true`, `DB_SSL_REJECT_UNAUTHORIZED`=`true` ;
- `pilot/ovhtest/database-migration` avec les mêmes clés et `DB_USER`=`ovhtest_migration`.

## Valkey

Créer l'utilisateur applicatif depuis le Manager/API OVHcloud. Le secret `pilot/ovhtest/valkey` contient une clé `REDIS_URL` au format `rediss://UTILISATEUR:MOT_DE_PASSE@HOTE:PORT`. Le code refuse une URL sans TLS sur Kubernetes.

## Registry

Créer une identité push réservée à GitHub et une identité pull réservée au cluster. Enregistrer les identifiants push dans les secrets GitHub `OVH_REGISTRY_PUSH_USERNAME` et `OVH_REGISTRY_PUSH_PASSWORD`; définir `OVH_REGISTRY_HOST` et `OVH_REGISTRY_REPOSITORY` comme variables GitHub.

Le secret `pilot/ovhtest/registry-pull` contient la propriété `.dockerconfigjson` avec le document Docker config JSON complet. ESO créera un Secret Kubernetes de type `kubernetes.io/dockerconfigjson`.

## Certificat mTLS ESO

Après le premier apply `platform`, créer le secret directement depuis les fichiers remis par OVHcloud :

```powershell
kubectl --kubeconfig .\kubeconfig-pilot.yaml -n external-secrets create secret tls ovhcloud-mtls --cert .\cert.pem --key .\key.pem --dry-run=client -o yaml | kubectl --kubeconfig .\kubeconfig-pilot.yaml apply -f -
kubectl --kubeconfig .\kubeconfig-pilot.yaml get clustersecretstore ovhcloud
```

Supprimer ensuite les copies locales non nécessaires selon votre politique de coffre. Ne jamais les ajouter au dépôt.

## Logs Data Platform

Après activation manuelle de la petite offre LDP et création du stream par Terraform, copier le write token dans `pilot/shared/ldp` sous la propriété `token`. Renseigner le hostname `graX.logs.ovh.com` dans le tfvars d'observabilité; le token reste exclusivement dans Secret Manager.
