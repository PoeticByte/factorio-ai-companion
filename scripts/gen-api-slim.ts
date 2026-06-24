#!/usr/bin/env bun
/**
 * Generate a slim Factorio runtime-API spec for offline linting.
 *
 * Source: the official runtime-api.json (vendored from the factorio-agent repo,
 * which mirrors Factorio's `--dump-data` runtime API). We only keep what the
 * Lua linter needs — the `defines.*` tree and the set of all class member names —
 * so the checked-in artifact stays a few KB instead of 3.5 MB.
 *
 * Run: bun run scripts/gen-api-slim.ts [path-to-runtime-api.json]
 * Default source path can be overridden by the first arg or FACTORIO_API env.
 */
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";

const SRC =
  process.argv[2] ||
  process.env.FACTORIO_API ||
  "C:/Project/factorio-agent/data/raw/runtime-api.json";
const OUT = "reference/factorio-api-slim.json";

type DefineNode = { values: string[]; subs: Record<string, DefineNode> };

function buildDefine(node: any): DefineNode {
  const out: DefineNode = { values: [], subs: {} };
  for (const v of node.values || []) out.values.push(v.name);
  for (const s of node.subkeys || []) out.subs[s.name] = buildDefine(s);
  return out;
}

function main() {
  const api = JSON.parse(readFileSync(SRC, "utf8"));

  const defines: Record<string, DefineNode> = {};
  for (const d of api.defines || []) defines[d.name] = buildDefine(d);

  // Flat set of every method/attribute name across all classes (for a softer
  // future check; cheap to keep, ~tens of KB).
  const members = new Set<string>();
  for (const c of api.classes || []) {
    for (const m of c.methods || []) members.add(m.name);
    for (const a of c.attributes || []) members.add(a.name);
  }

  const slim = {
    application: api.application,
    application_version: api.application_version,
    api_version: api.api_version,
    defines,
    members: [...members].sort(),
  };

  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(slim, null, 0));
  const define_count = Object.keys(defines).length;
  console.log(
    `✅ wrote ${OUT} (factorio ${api.application_version}, ${define_count} define roots, ${members.size} members)`
  );
}

main();
