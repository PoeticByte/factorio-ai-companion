#!/usr/bin/env bun
/**
 * Smoke-test the v0.21–v0.26 pillar features over RCON.
 *
 * Static checks (validate-tools, lint-lua-api) can't catch a command that crashes
 * or returns a silent error at runtime. This runs each new command against a live
 * game and reports PASS / FAIL / SKIP, so a human hosting the save can verify the
 * whole batch in one shot:
 *
 *   bun scripts/smoke-pillars.ts            # safe probes (no companion needed for most)
 *
 * Requires Factorio hosting a multiplayer game with RCON enabled (see scripts/rcon.ts).
 * Probes that need a companion are marked soft: "Companion not found" => SKIP, not FAIL.
 * Memory/plan probes clean up after themselves; nothing is left running.
 */
import { RCONClient } from "../src/rcon/client";
import { getRCONConfig } from "../src/config";

const client = new RCONClient(getRCONConfig());

let pass = 0, fail = 0, skip = 0;

type Opts = { soft?: boolean; expectKey?: string };

async function probe(label: string, cmd: string, opts: Opts = {}): Promise<any> {
  const full = cmd.startsWith("/") ? cmd : "/" + cmd;
  const res = await client.sendCommand(full);
  if (!res.success) {
    console.log(`  ❌ FAIL  ${label}\n        RCON error: ${res.error}`);
    fail++;
    return null;
  }
  let data: any = null;
  try {
    data = JSON.parse(res.data || "");
  } catch {
    console.log(`  ❌ FAIL  ${label}\n        non-JSON: ${String(res.data).slice(0, 120)}`);
    fail++;
    return null;
  }
  if (data && data.error) {
    if (opts.soft && /not found/i.test(String(data.error))) {
      console.log(`  ⏭️  SKIP  ${label} — ${data.error}`);
      skip++;
      return null;
    }
    console.log(`  ❌ FAIL  ${label} — error: ${data.error}`);
    fail++;
    return null;
  }
  if (opts.expectKey && data[opts.expectKey] === undefined) {
    console.log(`  ❌ FAIL  ${label} — missing key "${opts.expectKey}" in ${JSON.stringify(data).slice(0, 120)}`);
    fail++;
    return null;
  }
  console.log(`  ✅ PASS  ${label}  ${JSON.stringify(data).slice(0, 110)}`);
  pass++;
  return data;
}

async function main() {
  try {
    await client.connect();
  } catch (e) {
    console.error("Connection failed:", (e as Error).message);
    console.error("Is Factorio hosting a multiplayer game with RCON enabled?");
    process.exit(1);
  }

  console.log("🔬 Smoke-testing pillar features (v0.21–v0.26)\n");

  console.log("— meta —");
  await probe("version", "fac_version", { expectKey: "version" });
  await probe("overview", "fac_overview", { expectKey: "companions" });
  await probe("help", "fac_help", { expectKey: "categories" });

  console.log("\n— Pillar III: memory (no companion needed) —");
  await probe(
    "memory_remember location (x/y)",
    'fac_memory_remember {"type":"location","name":"smoke-spot","kind":"test","x":12,"y":34}',
    { expectKey: "remembered" }
  );
  await probe("memory_recall location", "fac_memory_recall location smoke", { expectKey: "locations" });
  await probe(
    "memory_remember pref",
    'fac_memory_remember {"type":"pref","key":"smoke-pref","value":"on"}',
    { expectKey: "remembered" }
  );
  await probe("memory_list", "fac_memory_list", { expectKey: "counts" });
  await probe("memory_forget location", "fac_memory_forget location smoke-spot", { expectKey: "forgot" });
  await probe("memory_forget pref", "fac_memory_forget pref smoke-pref", { expectKey: "forgot" });

  console.log("\n— Pillar II: plans (auto off — no side effects) —");
  const created = await probe(
    "plan_create (manual)",
    'fac_plan_create {"goal":"smoke","auto":false,"steps":["alpha","beta"]}',
    { expectKey: "plan" }
  );
  const pid = created?.plan?.id;
  if (pid !== undefined) {
    await probe(`plan_status ${pid}`, `fac_plan_status ${pid}`, { expectKey: "plan" });
    await probe(`plan_step_done ${pid}`, `fac_plan_step_done ${pid}`, { expectKey: "plan" });
    await probe(`plan_run ${pid} off`, `fac_plan_run ${pid} off`, { expectKey: "auto" });
  } else {
    console.log("  ⏭️  SKIP  plan_status/step_done/run — no plan id from create");
    skip += 3;
  }
  await probe("plan_status (list)", "fac_plan_status 0", { expectKey: "plans" });

  console.log("\n— Pillar I: factory doctor (needs companion #1) —");
  await probe("factory_analyze 1", "fac_factory_analyze 1", { soft: true, expectKey: "issues" });
  await probe("factory_graph 1", "fac_factory_graph 1", { soft: true, expectKey: "graph" });
  await probe("production_plan 1 electronic-circuit", "fac_production_plan 1 electronic-circuit 1", { soft: true, expectKey: "steps" });
  await probe("tech_path 1 automation", "fac_tech_path 1 automation", { soft: true, expectKey: "path" });

  console.log(`\n📊 ${pass} pass, ${fail} fail, ${skip} skip`);
  await client.disconnect();
  process.exit(fail > 0 ? 1 : 0);
}

main();
