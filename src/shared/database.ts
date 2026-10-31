import { Pool } from "pg";
import { envBoolean } from "./config.js";

export function createDatabasePool(): Pool {
  const useSsl = envBoolean("DB_SSL", false);

  return new Pool({
    host: process.env.DB_HOST ?? "127.0.0.1",
    port: Number(process.env.DB_PORT ?? 5432),
    user: process.env.DB_USER ?? "ovhtest_runtime",
    password: process.env.DB_PASSWORD ?? "",
    database: process.env.DB_NAME ?? "ovhtest",
    max: Number(process.env.DB_CONNECTION_LIMIT ?? 5),
    connectionTimeoutMillis: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 10_000),
    ssl: useSsl
      ? { rejectUnauthorized: envBoolean("DB_SSL_REJECT_UNAUTHORIZED", true) }
      : undefined,
  });
}
