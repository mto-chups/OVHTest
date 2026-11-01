import "dotenv/config";
import express from "express";
import { setTimeout as delay } from "node:timers/promises";
import { createDatabasePool } from "../shared/database.js";
import { reportStatus } from "../shared/status.js";

const serverUrl = process.env.SERVER_URL ?? `http://127.0.0.1:${process.env.SERVER_PORT ?? 3100}`;
const port = Number(process.env.MS2_PORT ?? 3002);
const statusIntervalMs = Number(process.env.STATUS_REPORT_INTERVAL_MS ?? 10_000);
const pool = createDatabasePool();
const app = express();
let ready = false;
let shuttingDown = false;

app.get("/health", (_request, response) => {
  response.status(ready ? 200 : 503).json({ service: "microservice-2", ok: ready });
});
const healthServer = app.listen(port, () => console.log(`Microservice 2 health endpoint listening on port ${port}`));

async function monitorDatabase(): Promise<void> {
  while (!shuttingDown) {
    try {
      const result = await pool.query<{ now: Date }>("SELECT NOW() AS now");
      const now = result.rows[0]?.now;
      if (!now) throw new Error("PostgreSQL n'a retourné aucune date");

      await reportStatus(
        serverUrl,
        "microservice-2",
        "ok",
        `PostgreSQL répond (${new Date(now).toISOString()})`,
      );

      if (!ready) console.log("Database and server status API checks succeeded");
      ready = true;
    } catch (error) {
      ready = false;
      console.error("Database check:", error);
    }

    if (!shuttingDown) await delay(statusIntervalMs);
  }
}

void monitorDatabase();

async function shutdown(): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  ready = false;
  healthServer.close();
  await pool.end();
}

process.once("SIGTERM", () => void shutdown());
process.once("SIGINT", () => void shutdown());
