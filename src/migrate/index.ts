import "dotenv/config";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { quotePostgresIdentifier } from "../shared/config.js";
import { createDatabasePool } from "../shared/database.js";

const pool = createDatabasePool();

async function migrate(): Promise<void> {
  const migrationPath = path.resolve(process.cwd(), "database", "migrations", "001_init.sql");
  const sql = await readFile(migrationPath, "utf8");
  const runtimeRole = quotePostgresIdentifier(process.env.DB_RUNTIME_USER ?? "ovhtest_runtime");
  const client = await pool.connect();

  try {
    await client.query("BEGIN");
    await client.query(sql);
    await client.query(`GRANT USAGE ON SCHEMA public TO ${runtimeRole}`);
    await client.query(`GRANT SELECT, INSERT ON TABLE deployment_checks TO ${runtimeRole}`);
    await client.query(`GRANT USAGE, SELECT ON SEQUENCE deployment_checks_id_seq TO ${runtimeRole}`);
    await client.query("COMMIT");
    console.log("PostgreSQL migration completed");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

void migrate()
  .then(() => pool.end())
  .catch(async (error) => {
    console.error(error);
    await pool.end();
    process.exitCode = 1;
  });
