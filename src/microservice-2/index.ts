import "dotenv/config";
import type { RowDataPacket } from "mysql2";
import { createDatabasePool } from "../shared/database.js";
import { reportStatus, retry } from "../shared/status.js";

const serverUrl = process.env.SERVER_URL ?? `http://127.0.0.1:${process.env.SERVER_PORT ?? 3100}`;
const pool = createDatabasePool();

void retry(async () => {
  const [rows] = await pool.query<(RowDataPacket & { now: Date })[]>("SELECT NOW() AS now");
  await reportStatus(
    serverUrl,
    "microservice-2",
    "ok",
    `MySQL/MariaDB répond (${new Date(rows[0].now).toISOString()})`,
  );
  console.log("Database and server status API checks succeeded");
}, "Database check");
