export function envBoolean(name: string, defaultValue: boolean): boolean {
  const value = process.env[name];
  return value === undefined ? defaultValue : value.toLowerCase() === "true";
}

export function redisChannel(name: string): string {
  const prefix = (process.env.REDIS_PREFIX ?? process.env.REDIS_KEY_PREFIX ?? "ovhtest").replace(/:+$/, "");
  return `${prefix}:${name}`;
}

export function redisUrl(): string {
  const value = process.env.REDIS_URL ?? "redis://127.0.0.1:6379";
  const tlsRequired = envBoolean("REDIS_TLS_REQUIRED", process.env.NODE_ENV === "production");
  const parsed = new URL(value);

  if (!["redis:", "rediss:"].includes(parsed.protocol)) {
    throw new Error("REDIS_URL must use redis:// or rediss://");
  }
  if (tlsRequired && parsed.protocol !== "rediss:") {
    throw new Error("REDIS_URL must use rediss:// when REDIS_TLS_REQUIRED is enabled");
  }
  return value;
}

export function quotePostgresIdentifier(value: string): string {
  if (!/^[a-z_][a-z0-9_]*$/i.test(value)) {
    throw new Error(`Invalid PostgreSQL identifier: ${value}`);
  }
  return `"${value.replaceAll('"', '""')}"`;
}
