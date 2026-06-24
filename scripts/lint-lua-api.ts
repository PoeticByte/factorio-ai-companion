#!/usr/bin/env bun
/**
 * Lint the mod's Lua against the real Factorio runtime API.
 *
 * Catches the "silent nil → no reaction" bug class noted in project memory: a
 * mistyped `defines.*` path (e.g. defines.inventory.character_ammos) resolves to
 * nil at runtime with NO error — the command just does nothing. In-game errors
 * are invisible in the console, so this check pays for itself before the (manual,
 * host-required) test loop.
 *
 * Validates every `defines.<dotted.path>` reference in factorio-mod/**.lua against
 * the vendored slim API tree (reference/factorio-api-slim.json).
 *
 * Run: bun run scripts/lint-lua-api.ts
 */
import { readFileSync, readdirSync, statSync } from "fs";
import { join } from "path";

type DefineNode = { values: string[]; subs: Record<string, DefineNode> };

const LUA_DIR = "factorio-mod";
const SLIM = "reference/factorio-api-slim.json";

const slim = JSON.parse(readFileSync(SLIM, "utf8")) as {
  application_version: string;
  defines: Record<string, DefineNode>;
};

function luaFiles(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...luaFiles(p));
    else if (name.endsWith(".lua")) out.push(p);
  }
  return out;
}

// Validate a dotted path after `defines.`. Returns null if OK, else a reason.
function checkDefinePath(path: string): string | null {
  const parts = path.split(".");
  const root = slim.defines[parts[0]];
  if (!root) return `unknown defines root "${parts[0]}"`;
  let node = root;
  for (let i = 1; i < parts.length; i++) {
    const part = parts[i];
    if (node.values.includes(part)) {
      // Reached a leaf enum value; nothing may be indexed beyond it.
      if (i !== parts.length - 1)
        return `"${part}" is a value, cannot index ".${parts[i + 1]}" under it`;
      return null;
    }
    if (node.subs[part]) {
      node = node.subs[part];
      continue;
    }
    return `unknown member "${part}" under defines.${parts.slice(0, i).join(".")}`;
  }
  return null; // path ended at a valid namespace/leaf
}

// Strip a trailing single-line Lua comment (best effort; ignores -- inside strings,
// which this codebase doesn't mix with defines references).
function stripComment(line: string): string {
  const i = line.indexOf("--");
  return i >= 0 ? line.slice(0, i) : line;
}

function main() {
  const files = luaFiles(LUA_DIR);
  const re = /defines\.([A-Za-z_][A-Za-z0-9_.]*)/g;
  let errors = 0;
  let checked = 0;

  console.log(
    `🔍 Linting Lua defines.* against Factorio ${slim.application_version} API...\n`
  );

  for (const file of files) {
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    lines.forEach((raw, idx) => {
      const line = stripComment(raw);
      let m: RegExpExecArray | null;
      re.lastIndex = 0;
      while ((m = re.exec(line)) !== null) {
        let path = m[1];
        // Trim a trailing dot (e.g. "defines.events." mid-expression edge).
        path = path.replace(/\.+$/, "");
        if (!path) continue;
        checked++;
        const reason = checkDefinePath(path);
        if (reason) {
          console.log(`  ❌ ${file}:${idx + 1}  defines.${path}  — ${reason}`);
          errors++;
        }
      }
    });
  }

  console.log(`\n📊 Checked ${checked} defines.* references in ${files.length} files.`);
  if (errors === 0) {
    console.log("✅ All defines.* paths are valid.");
  } else {
    console.log(`\n❌ Found ${errors} invalid defines.* path(s).`);
    process.exit(1);
  }
}

main();
