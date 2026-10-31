import "dotenv/config";
import express from "express";
import { createServer } from "node:http";
import { createClient } from "redis";
import { WebSocket, WebSocketServer } from "ws";
import { redisChannel, redisUrl } from "../shared/config.js";
import { createDatabasePool } from "../shared/database.js";
import type { ServiceState, ServiceStatus } from "../shared/status.js";
import { retry } from "../shared/status.js";
import { ui } from "./ui.js";

const port = Number(process.env.SERVER_PORT ?? process.env.PORT ?? 3100);
const valkeyUrl = redisUrl();
const ms1Url = process.env.MS1_URL ?? `http://127.0.0.1:${process.env.MS1_PORT ?? 3001}`;

const app = express();
const httpServer = createServer(app);
const wsServer = new WebSocketServer({ server: httpServer, path: "/ws" });
const pool = createDatabasePool();
const redisPublisher = createClient({ url: valkeyUrl });
const redisSubscriber = redisPublisher.duplicate();
const statuses = new Map<string, ServiceStatus>();
let databaseReady = false;
let redisReady = false;
let shuttingDown = false;

app.use(express.json());
app.get("/", (_request, response) => response.type("html").send(ui));
app.get("/api/live", (_request, response) => response.json({ ok: true }));
app.get("/api/health", (_request, response) => {
  const ok = databaseReady && redisReady;
  response.status(ok ? 200 : 503).json({ ok, databaseReady, redisReady });
});
app.get("/api/status", (_request, response) => response.json(Object.fromEntries(statuses)));
app.post("/api/status", (request, response) => {
  const { name, state, message } = request.body as Partial<ServiceStatus>;
  if (!name || !message || !["starting", "ok", "error"].includes(state ?? "")) {
    response.status(400).json({ error: "name, state et message sont requis" });
    return;
  }
  updateStatus(name, state as ServiceState, message);
  response.status(204).end();
});

function updateStatus(name: string, state: ServiceState, message: string): void {
  statuses.set(name, { name, state, message, updatedAt: new Date().toISOString() });
  const payload = JSON.stringify(Object.fromEntries(statuses));
  for (const client of wsServer.clients) {
    if (client.readyState === WebSocket.OPEN) client.send(payload);
  }
}

wsServer.on("connection", (socket) => socket.send(JSON.stringify(Object.fromEntries(statuses))));

async function checkMainDatabase(): Promise<void> {
  updateStatus("server-db", "starting", "Test PostgreSQL en cours…");
  const inserted = await pool.query<{ id: string }>(
    "INSERT INTO deployment_checks(message) VALUES($1) RETURNING id",
    [`Test serveur ${new Date().toISOString()}`],
  );
  const id = inserted.rows[0]?.id;
  if (!id) throw new Error("PostgreSQL n'a retourné aucun identifiant");
  const selected = await pool.query<{ id: string; message: string }>(
    "SELECT id, message FROM deployment_checks WHERE id = $1",
    [id],
  );
  if (!selected.rows[0]) throw new Error("La ligne insérée n'a pas été retrouvée");
  databaseReady = true;
  updateStatus("server-db", "ok", `INSERT + SELECT réussis (id ${id})`);
}

async function setupRedis(): Promise<void> {
  await Promise.all([redisPublisher.connect(), redisSubscriber.connect()]);
  await redisSubscriber.subscribe(redisChannel("deployment:pong"), (message) => {
    updateStatus("microservice-3", "ok", `Réponse Valkey reçue : ${message}`);
  });
  redisReady = true;
  updateStatus("valkey-channel", "ok", "Connecté au canal Valkey");
  setInterval(
    () => void redisPublisher.publish(redisChannel("deployment:ping"), new Date().toISOString()),
    5_000,
  ).unref();
  await redisPublisher.publish(redisChannel("deployment:ping"), new Date().toISOString());
}

async function checkMicroservice1(): Promise<void> {
  const response = await fetch(`${ms1Url}/health`);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  updateStatus("microservice-1", "ok", "API HTTP joignable par le serveur");
}

async function shutdown(): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  databaseReady = false;
  redisReady = false;
  httpServer.close();
  await Promise.allSettled([redisPublisher.quit(), redisSubscriber.quit(), pool.end()]);
}

httpServer.listen(port, () => console.log(`Server listening on http://localhost:${port}`));
redisPublisher.on("error", (error) => console.error("Valkey publisher:", error));
redisSubscriber.on("error", (error) => console.error("Valkey subscriber:", error));
updateStatus("server", "ok", `API et WebSocket disponibles sur le port ${port}`);
updateStatus("microservice-1", "starting", "En attente de l'API HTTP…");
updateStatus("microservice-2", "starting", "En attente du test PostgreSQL…");
updateStatus("microservice-3", "starting", "En attente du message Valkey…");

void retry(checkMainDatabase, "Main database check");
void retry(setupRedis, "Valkey setup");
void retry(checkMicroservice1, "Microservice 1 check");
process.once("SIGTERM", () => void shutdown());
process.once("SIGINT", () => void shutdown());
