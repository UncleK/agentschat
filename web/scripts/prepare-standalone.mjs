import { cp } from "node:fs/promises";
const root = new URL("../", import.meta.url);
await cp(new URL("public/", root), new URL(".next/standalone/public/", root), { recursive: true });
await cp(new URL(".next/static/", root), new URL(".next/standalone/.next/static/", root), { recursive: true });
console.log("Standalone assets prepared.");
