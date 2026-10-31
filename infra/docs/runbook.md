# Runbook du pilote

## Garde-fous

Ce pilote contient uniquement des données de test. PostgreSQL et Valkey Essential sont mono-nœud ; PostgreSQL ne conserve que deux jours de sauvegardes natives. Les ressources state, bases, Registry et OKMS utilisent `prevent_destroy`. Ne lever une protection que dans une modification dédiée et relue.

Les namespaces applicatif, Traefik, cert-manager et External Secrets imposent Pod Security `restricted`. Le namespace `logging` est l'unique exception explicite : Fluent Bit DaemonSet doit monter les journaux du nœud via `hostPath`; il impose donc `privileged` tout en conservant `audit` et `warn` à `restricted`.

## Rotation d'un secret

Créer une nouvelle version dans Secret Manager, attendre que l'ExternalSecret soit `Ready`, vérifier le Secret Kubernetes sans afficher sa valeur, puis redémarrer uniquement le Deployment concerné au moyen d'un changement Terraform de l'annotation `secret-revision`. Vérifier les probes et les logs. Ne jamais exécuter `kubectl set image` ou `helm upgrade` hors procédure d'urgence.

## Rollback applicatif

Remettre l'ancien digest immuable dans `versions.auto.tfvars`, produire un plan, le relire, appliquer le fichier de plan, puis contrôler les quatre endpoints de santé et le WebSocket. Une migration destructive est interdite dans ce pilote ; les migrations doivent rester rétrocompatibles.

## Restauration PostgreSQL

Depuis le Manager OVHcloud, sélectionner une sauvegarde native disponible, restaurer vers un service temporaire, vérifier l'intégrité avec le rôle migration, puis basculer les secrets seulement après validation. Documenter l'heure de sauvegarde, l'heure de restauration et la perte de données constatée. Supprimer le service temporaire uniquement après validation explicite.

## Incident Terraform

Ne jamais supprimer manuellement un lock récent. Identifier d'abord le processus détenteur. Pour un lock réellement orphelin, utiliser `terraform force-unlock ID` après copie du state versionné. En cas de state endommagé, restaurer une version S3 antérieure dans un environnement isolé et exécuter un plan avant toute remise en production.
