# OVHTest

Pilote Node.js/TypeScript composé d'un serveur principal et de trois microservices. La cible cloud est OVHcloud MKS avec PostgreSQL et Valkey managés ; l'environnement local Docker Compose fournit PostgreSQL et Redis compatibles.

## Développement local

Prérequis : Node.js 22+ ou Docker avec Compose.

```powershell
docker compose up --build
```

L'interface est disponible sur <http://localhost:3000>. Le service `migrate` applique d'abord la migration PostgreSQL idempotente, puis les quatre composants démarrent. Pour vérifier le code hors conteneur :

```powershell
npm ci
npm test
```

## Contrats applicatifs

- `server` écoute sur `PORT` (3000) et expose `/api/health`, `/api/live`, `/api/status` et `/ws`.
- `microservice-1` écoute sur `PORT` (3001) et expose `/health`.
- `microservice-2` écoute sur `MS2_PORT` (3002) et expose `/health`.
- `microservice-3` écoute sur `MS3_PORT` (3003) et expose `/health`.
- PostgreSQL utilise `DB_HOST`, `DB_PORT` (5432), `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_SSL` et `DB_SSL_REJECT_UNAUTHORIZED`.
- Valkey utilise `REDIS_URL`; sur OVHcloud cette URL doit commencer par `rediss://`. Les canaux sont préfixés par `REDIS_PREFIX` (`ovhtest` par défaut).

Le processus de migration utilise un compte DDL distinct et reçoit `DB_RUNTIME_USER` pour accorder uniquement les droits nécessaires au rôle d'exécution.

## Déploiement OVHcloud

Toute l'IaC et le guide pas à pas sont dans [infra/README.md](infra/README.md). Aucun `terraform apply` n'est exécuté par la CI : les plans sont relus et appliqués localement, état par état.
