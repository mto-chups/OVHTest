import "dotenv/config";
import express from "express";
import { createServer } from "node:http";
import { createClient } from "redis";
import { WebSocket, WebSocketServer } from "ws";
import type { ResultSetHeader, RowDataPacket } from "mysql2";
import { createDatabasePool } from "../shared/database.js";
import type { ServiceState, ServiceStatus } from "../shared/status.js";
import { retry } from "../shared/status.js";
import { ui } from "./ui.js";

const port = Number(process.env.SERVER_PORT ?? process.env.PORT ?? 3100);
const redisUrl = process.env.REDIS_URL ?? "redis://localhost:6379";
const ms1Url = process.env.MS1_URL ?? `http://127.0.0.1:${process.env.MS1_PORT ?? 3001}`;

const app = express();
const httpServer = createServer(app);
const wsServer = new WebSocketServer({ server: httpServer, path: "/ws" });
const pool = createDatabasePool();
const redisPublisher = createClient({ url: redisUrl });
const redisSubscriber = redisPublisher.duplicate();
const statuses = new Map<string, ServiceStatus>();

app.use(express.json());
app.get("/", (_request, response) => response.type("html").send(ui));
app.get("/api/health", (_request, response) => response.json({ ok: true }));
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
  updateStatus("server-db", "starting", "Création de la table et test SQL…");
  const connection = await pool.getConnection();
  try {
    await connection.query(`CREATE TABLE IF NOT EXISTS deployment_checks (
      id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
      message VARCHAR(255) NOT NULL
    )`);
    const [inserted] = await connection.execute<ResultSetHeader>(
      "INSERT INTO deployment_checks(message) VALUES(?)",
      [`Test serveur ${new Date().toISOString()}`],
    );
    const [selected] = await connection.execute<(RowDataPacket & { id: number; message: string })[]>(
      "SELECT id, message FROM deployment_checks WHERE id = ?",
      [inserted.insertId],
    );
    if (!selected[0]) throw new Error("La ligne insérée n'a pas été retrouvée");
    updateStatus("server-db", "ok", `INSERT + SELECT réussis (id ${selected[0].id})`);
  } finally {
    connection.release();
  }
}

async function setupRedis(): Promise<void> {
  await Promise.all([redisPublisher.connect(), redisSubscriber.connect()]);
  await redisSubscriber.subscribe("deployment:pong", (message) => {
    updateStatus("microservice-3", "ok", `Réponse Redis reçue : ${message}`);
  });
  updateStatus("redis-channel", "ok", "Connecté au canal Redis");
  setInterval(() => void redisPublisher.publish("deployment:ping", new Date().toISOString()), 5_000);
  await redisPublisher.publish("deployment:ping", new Date().toISOString());
}

async function checkMicroservice1(): Promise<void> {
  const response = await fetch(`${ms1Url}/health`);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  updateStatus("microservice-1", "ok", "API HTTP joignable par le serveur");
}

httpServer.listen(port, () => console.log(`Server listening on http://localhost:${port}`));
redisPublisher.on("error", (error) => console.error("Redis publisher:", error));
redisSubscriber.on("error", (error) => console.error("Redis subscriber:", error));
updateStatus("server", "ok", `API et WebSocket disponibles sur le port ${port}`);
updateStatus("microservice-1", "starting", "En attente de l'API HTTP…");
updateStatus("microservice-2", "starting", "En attente du test MySQL/MariaDB…");
updateStatus("microservice-3", "starting", "En attente du message Redis…");

void retry(checkMainDatabase, "Main database check");
void retry(setupRedis, "Redis setup");
void retry(checkMicroservice1, "Microservice 1 check");
