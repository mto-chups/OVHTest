import assert from "node:assert/strict";
import test from "node:test";
import { envBoolean, quotePostgresIdentifier, redisChannel, redisUrl } from "./config.js";

test("envBoolean uses defaults and explicit values", () => {
  delete process.env.TEST_BOOLEAN;
  assert.equal(envBoolean("TEST_BOOLEAN", true), true);
  process.env.TEST_BOOLEAN = "false";
  assert.equal(envBoolean("TEST_BOOLEAN", true), false);
  delete process.env.TEST_BOOLEAN;
});

test("redisChannel normalizes the configured prefix", () => {
  process.env.REDIS_PREFIX = "pilot:::";
  assert.equal(redisChannel("deployment:ping"), "pilot:deployment:ping");
  delete process.env.REDIS_PREFIX;
});

test("quotePostgresIdentifier rejects unsafe values", () => {
  assert.equal(quotePostgresIdentifier("ovhtest_runtime"), '"ovhtest_runtime"');
  assert.throws(() => quotePostgresIdentifier("runtime; DROP TABLE users"));
});

test("redisUrl requires TLS when configured", () => {
  process.env.REDIS_TLS_REQUIRED = "true";
  process.env.REDIS_URL = "redis://cache.example:6379";
  assert.throws(() => redisUrl(), /rediss/);
  process.env.REDIS_URL = "rediss://cache.example:6379";
  assert.equal(redisUrl(), "rediss://cache.example:6379");
  delete process.env.REDIS_TLS_REQUIRED;
  delete process.env.REDIS_URL;
});
