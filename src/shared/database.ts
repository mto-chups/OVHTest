import mysql, { type Pool } from "mysql2/promise";

function envBoolean(name: string, defaultValue: boolean): boolean {
  const value = process.env[name];
  return value === undefined ? defaultValue : value.toLowerCase() === "true";
}

export function createDatabasePool(): Pool {
  const useSsl = envBoolean("DB_SSL", false);

  return mysql.createPool({
    host: process.env.DB_HOST ?? "127.0.0.1",
    port: Number(process.env.DB_PORT ?? 3306),
    user: process.env.DB_USER ?? "root",
    password: process.env.DB_PASSWORD ?? "",
    database: process.env.DB_NAME ?? "deployment_test",
    waitForConnections: true,
    connectionLimit: Number(process.env.DB_CONNECTION_LIMIT ?? 5),
    connectTimeout: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 10_000),
    ssl: useSsl
      ? { rejectUnauthorized: envBoolean("DB_SSL_REJECT_UNAUTHORIZED", true) }
      : undefined,
  });
}
