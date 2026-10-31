import "dotenv/config";
import express from "express";
import { reportStatus, retry } from "../shared/status.js";

const port = Number(process.env.MS1_PORT ?? process.env.PORT ?? 3001);
const serverUrl = process.env.SERVER_URL ?? `http://127.0.0.1:${process.env.SERVER_PORT ?? 3100}`;
const app = express();

app.get("/health", (_request, response) => response.json({ service: "microservice-1", ok: true }));
app.listen(port, () => console.log(`Microservice 1 listening on port ${port}`));

void retry(async () => {
  const response = await fetch(`${serverUrl}/api/health`);
  if (!response.ok) throw new Error(`Server returned HTTP ${response.status}`);
  await reportStatus(serverUrl, "microservice-1", "ok", "Serveur principal joint via son API");
}, "Server API check");
