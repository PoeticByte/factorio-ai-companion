#!/usr/bin/env bun
/**
 * One-shot RCON sender for debugging. Prints the raw JSON the mod returns
 * (including error responses that are invisible in the in-game console).
 *
 * Usage:
 *   bun scripts/rcon.ts "fac_companion_spawn id=1"
 *   bun scripts/rcon.ts "fac_move_to 1 30 30"
 *   bun scripts/rcon.ts "fac_companion_status 1"
 *
 * Requires Factorio hosting a multiplayer game with RCON enabled in
 * %APPDATA%/Factorio/config/config.ini:
 *   local-rcon-socket=127.0.0.1:34198
 *   local-rcon-password=factorio
 */
import { RCONClient } from "../src/rcon/client";
import { getRCONConfig } from "../src/config";

const raw = process.argv.slice(2).join(" ").trim();
if (!raw) {
  console.error('Usage: bun scripts/rcon.ts "<command>"');
  console.error('  e.g. bun scripts/rcon.ts "fac_move_to 1 30 30"');
  process.exit(1);
}
const command = raw.startsWith("/") ? raw : "/" + raw;

const client = new RCONClient(getRCONConfig());
try {
  await client.connect();
  console.log(`> ${command}`);
  const res = await client.sendCommand(command);
  if (res.success) {
    console.log(res.data ?? "(no data returned)");
  } else {
    console.error("ERROR:", res.error);
  }
} catch (e) {
  console.error("Connection failed:", (e as Error).message);
  console.error("Is Factorio hosting a multiplayer game with RCON enabled in config.ini?");
} finally {
  await client.disconnect();
}
