export type ServiceState = "starting" | "ok" | "error";

export interface ServiceStatus {
  name: string;
  state: ServiceState;
  message: string;
  updatedAt: string;
}

export async function reportStatus(
  serverUrl: string,
  name: string,
  state: ServiceState,
  message: string,
): Promise<void> {
  const response = await fetch(`${serverUrl}/api/status`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name, state, message }),
  });

  if (!response.ok) {
    const details = (await response.text()).replace(/\s+/g, " ").trim().slice(0, 300);
    throw new Error(
      `Status report rejected by ${serverUrl}/api/status: HTTP ${response.status}` +
        (details ? ` - ${details}` : ""),
    );
  }
}

export async function retry(
  task: () => Promise<void>,
  label: string,
  delayMs = 2_000,
): Promise<void> {
  for (;;) {
    try {
      await task();
      return;
    } catch (error) {
      // AggregateError (fréquent pour ECONNREFUSED sur IPv4 + IPv6) peut avoir
      // un message vide : inspect permet de conserver les vraies causes.
      console.error(`${label}: ${inspect(error, { depth: 4 })}`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}
import { inspect } from "node:util";
