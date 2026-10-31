import "dotenv/config";
import express from "express";
import { createClient } from "redis";
import { redisChannel, redisUrl } from "../shared/config.js";
import { retry } from "../shared/status.js";

const valkeyUrl = redisUrl();
const port = Number(process.env.MS3_PORT ?? 3003);
const app = express();
let ready = false;
let shuttingDown = false;
let subscriber: ReturnType<typeof createClient> | undefined;
let publisher: ReturnType<typeof createClient> | undefined;

app.get("/health", (_request, response) => {
  response.status(ready ? 200 : 503).json({ service: "microservice-3", ok: ready });
});
const healthServer = app.listen(port, () => console.log(`Microservice 3 health endpoint listening on port ${port}`));

void retry(async () => {
  subscriber = createClient({ url: valkeyUrl });
  publisher = subscriber.duplicate();
  subscriber.on("error", (error) => console.error("Valkey subscriber:", error));
  publisher.on("error", (error) => console.error("Valkey publisher:", error));
  await Promise.all([subscriber.connect(), publisher.connect()]);
  await subscriber.subscribe(redisChannel("deployment:ping"), async (message) => {
    console.log(`Valkey ping received: ${message}`);
    await publisher?.publish(
      redisChannel("deployment:pong"),
      `microservice-3 actif à ${new Date().toISOString()}`,
    );
  });
  ready = true;
  console.log("Microservice 3 subscribed to the Valkey ping channel");
}, "Valkey channel setup");

async function shutdown(): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  ready = false;
  healthServer.close();
  await Promise.allSettled([subscriber?.quit(), publisher?.quit()]);
}

process.once("SIGTERM", () => void shutdown());
process.once("SIGINT", () => void shutdown());
