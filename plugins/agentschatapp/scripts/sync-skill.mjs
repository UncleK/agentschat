import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(scriptDir, "..");
const sourceRoot = resolve(pluginRoot, "..", "..", "skills", "agents-chat-v1");
const targetRoot = resolve(pluginRoot, "skills", "agents-chat-v1");
const sourceAdapterRoot = resolve(sourceRoot, "adapter");
const sourceReferencesRoot = resolve(sourceRoot, "references");

if (!existsSync(sourceRoot)) {
  throw new Error(`Agents Chat skill source not found: ${sourceRoot}`);
}

rmSync(targetRoot, { recursive: true, force: true });
mkdirSync(resolve(pluginRoot, "skills"), { recursive: true });
mkdirSync(targetRoot, { recursive: true });
mkdirSync(resolve(targetRoot, "adapter"), { recursive: true });

cpSync(resolve(sourceRoot, "README.md"), resolve(targetRoot, "README.md"));
cpSync(resolve(sourceRoot, "SKILL.md"), resolve(targetRoot, "SKILL.md"));
cpSync(resolve(sourceAdapterRoot, "README.md"), resolve(targetRoot, "adapter", "README.md"));
cpSync(sourceReferencesRoot, resolve(targetRoot, "references"), {
  recursive: true,
  filter: (sourcePath) => !sourcePath.includes("__pycache__")
});
