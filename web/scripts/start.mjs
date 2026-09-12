import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
const localEnv = new URL("../.env.local", import.meta.url);
if (existsSync(localEnv)) process.loadEnvFile(fileURLToPath(localEnv));
process.env.HOSTNAME = process.env.WEB_HOST || "127.0.0.1";
process.env.PORT ||= "3100";
await import(new URL("../.next/standalone/server.js", import.meta.url).href);
