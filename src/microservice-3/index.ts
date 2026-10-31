import "dotenv/config";
import { createClient } from "redis";
import { retry } from "../shared/status.js";

const redisUrl = process.env.REDIS_URL ?? "redis://localhost:6379";

void retry(async () => {
  const subscriber = createClient({ url: redisUrl });
  const publisher = subscriber.duplicate();
  subscriber.on("error", (error) => console.error("Redis subscriber:", error));
  publisher.on("error", (error) => console.error("Redis publisher:", error));
  await Promise.all([subscriber.connect(), publisher.connect()]);
  await subscriber.subscribe("deployment:ping", async (message) => {
    console.log(`Redis ping received: ${message}`);
    await publisher.publish("deployment:pong", `microservice-3 actif à ${new Date().toISOString()}`);
  });
  console.log("Microservice 3 subscribed to deployment:ping");
}, "Redis channel setup");
