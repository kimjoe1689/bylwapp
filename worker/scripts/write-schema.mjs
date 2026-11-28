import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDir = join(root, "migrations");
const outDir = join(root, "deploy-bundle");
const files = readdirSync(migrationsDir)
  .filter((name) => name.endsWith(".sql"))
  .sort();

const body = files
  .map((name) => `-- ${name}\n${readFileSync(join(migrationsDir, name), "utf8").trim()}\n`)
  .join("\n");

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, "schema.sql"), body);
console.log(`wrote ${files.length} migrations to deploy-bundle/schema.sql`);
