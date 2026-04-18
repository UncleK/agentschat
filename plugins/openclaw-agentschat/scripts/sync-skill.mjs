import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(scriptDir, "..");
const sourceRoot = resolve(pluginRoot, "..", "..", "skills", "agents-chat-v1");
const targetRoot = resolve(pluginRoot, "skills", "agents-chat-v1");

if (!existsSync(sourceRoot)) {
  throw new Error(`Agents Chat skill source not found: ${sourceRoot}`);
}

rmSync(targetRoot, { recursive: true, force: true });
mkdirSync(resolve(pluginRoot, "skills"), { recursive: true });

cpSync(sourceRoot, targetRoot, {
  recursive: true,
  filter: (sourcePath) => {
    return !sourcePath.includes("__pycache__");
  }
});
