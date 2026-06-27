#!/usr/bin/env bun
/**
 * Launch the AI companion crew as a HEADLESS, AUTONOMOUS dedicated server —
 * no human host, no GUI. Companions spawn from the map spawn point (v0.27.0+),
 * and Claude/the orchestrator drives the entire colony over RCON.
 *
 *   bun run headless            # create the save if missing, then start the server
 *
 * Then, in another shell, drive it:
 *   bun run smoke               # verify the command surface
 *   bun scripts/rcon.ts "fac_companion_spawn id=1"
 *   ... issue plans / factory_fix / etc.
 *
 * Env overrides:
 *   FACTORIO_EXE   path to factorio.exe (default: Steam location)
 *   FAC_SAVE       save path (default: %APPDATA%/Factorio/saves/autonomous.zip)
 *   RCON_PORT      default 34198 (matches scripts/config + config.ini)
 *   RCON_PASSWORD  default "factorio"
 *
 * Key detail: server-settings has auto_pause=false, so the simulation keeps
 * ticking with ZERO players connected — otherwise the crew would freeze. A human
 * can optionally Multiplayer→Connect to this server (127.0.0.1) just to spectate;
 * the bot doesn't depend on it.
 */
import { spawn, spawnSync } from "child_process";
import { existsSync } from "fs";

const EXE =
  process.env.FACTORIO_EXE ||
  "D:/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio.exe";
const APPDATA = (process.env.APPDATA || "").replace(/\\/g, "/");
const SAVE = process.env.FAC_SAVE || `${APPDATA}/Factorio/saves/autonomous.zip`;
const SETTINGS = "scripts/headless/server-settings.json";
const RCON_PORT = process.env.RCON_PORT || "34198";
const RCON_PW = process.env.RCON_PASSWORD || "factorio";

if (!existsSync(EXE)) {
  console.error(`factorio.exe not found at: ${EXE}\nSet FACTORIO_EXE to your install path.`);
  process.exit(1);
}

if (!existsSync(SAVE)) {
  console.log(`📦 Creating map save: ${SAVE}`);
  const r = spawnSync(EXE, ["--create", SAVE], { stdio: "inherit" });
  if (r.status !== 0) {
    console.error("Map creation failed.");
    process.exit(1);
  }
}

console.log(`🤖 Starting headless autonomous server (RCON ${RCON_PORT})...`);
console.log("   auto_pause=false → sim runs with no players. Ctrl+C to stop.\n");
const srv = spawn(
  EXE,
  [
    "--start-server", SAVE,
    "--rcon-port", RCON_PORT,
    "--rcon-password", RCON_PW,
    "--server-settings", SETTINGS,
  ],
  { stdio: "inherit" }
);
srv.on("exit", (code) => process.exit(code ?? 0));
