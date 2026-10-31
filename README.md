# Test de déploiement minimal

Petit projet Node.js/TypeScript composé d'un serveur principal, de trois microservices, de MySQL/MariaDB et de Redis.

## Architecture

- **server** (`:3000`) : API Express, interface HTML et WebSocket. Au démarrage, il crée la table `deployment_checks`, insère une ligne, puis la relit.
- **microservice-1** (`:3001`) : expose une API HTTP et vérifie l'API du serveur principal.
- **microservice-2** : exécute un `SELECT NOW()` dans MySQL/MariaDB et transmet son état au serveur.
- **microservice-3** : écoute `deployment:ping` dans Redis et répond sur `deployment:pong`.
- **Redis** : lancé par Docker Compose. La base est fournie par WAMP ou par un service MySQL managé.

## Lancer le projet

Prérequis : Docker avec Docker Compose et WAMP démarré. Exécuter une fois `database/setup-wamp.sql` dans phpMyAdmin : ce script crée la base et un utilisateur accessible depuis Docker. Changez son mot de passe dans le SQL et dans le fichier `.env`.

Copier la configuration WAMP pour Docker :

```bash
copy .env.docker-wamp.example .env
```

```bash
docker compose up --build
```

Ouvrir ensuite <http://localhost:3000>. Les cartes se mettent à jour automatiquement via WebSocket.

Pour arrêter :

```bash
docker compose down
```

## API utile

- `GET /api/health` : santé du serveur.
- `GET /api/status` : dernier état connu de tous les composants.
- `POST /api/status` : remontée d'un état par un microservice.
- `WS /ws` : diffusion temps réel des états.

## Développement local

La commande `npm run dev` lance simultanément le serveur et les trois microservices, avec des logs préfixés. Les scripts individuels `npm run dev:server`, `dev:ms1`, `dev:ms2` et `dev:ms3` restent disponibles. Copier `.env.example` vers `.env`. MySQL/MariaDB et Redis doivent être joignables aux adresses configurées.

En développement local, le serveur principal écoute sur <http://localhost:3100> et MS1 sur le port `3001`. Docker conserve <http://localhost:3000> grâce à ses variables propres. `SERVER_PORT` et `MS1_PORT` sont séparés afin que les deux processus ne se disputent jamais une variable `PORT` commune.

Si Redis affiche `ECONNREFUSED` en lancement npm, démarrez Redis séparément ou lancez l'ensemble avec Docker Compose, qui fournit déjà le conteneur Redis. Les erreurs imbriquées Redis sont affichées intégralement pour faciliter le diagnostic.

En lancement Docker, il ne faut pas remplacer `REDIS_URL=redis://redis:6379` par `localhost` : dans un conteneur, `localhost` désigne le conteneur lui-même. En lancement npm hors Docker, utilisez bien `redis://127.0.0.1:6379` et démarrez Redis avec `docker compose up -d redis`.

Pour OVH, partir de `.env.ovh.example`. Le code utilise les mêmes variables `DB_*` et active TLS avec `DB_SSL=true`, sans changement applicatif.
