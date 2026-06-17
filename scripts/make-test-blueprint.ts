#!/usr/bin/env bun
/**
 * Emit a Factorio 2.0 blueprint export string for testing fac_blueprint_place.
 * Default: a row of 5 transport-belts. A Factorio blueprint string is
 *   "0" + base64( zlib-deflate( JSON ) ).
 *
 * Usage: bun scripts/make-test-blueprint.ts
 */
import { deflateSync } from "zlib";

const name = process.argv[2] || "transport-belt";
const count = parseInt(process.argv[3] || "5", 10);

// Factorio 2.0 directions are 16-step: N=0, E=4, S=8, W=12.
const entities = [];
for (let i = 0; i < count; i++) {
  entities.push({
    entity_number: i + 1,
    name,
    position: { x: i + 0.5, y: 0.5 },
    direction: 4, // east
  });
}

const bp = {
  blueprint: {
    icons: [{ signal: { type: "item", name }, index: 1 }],
    entities,
    item: "blueprint",
    version: 2 * 2 ** 48 + 28 * 2 ** 16, // 2.0.28-ish; import is lenient
  },
};

const json = JSON.stringify(bp);
const str = "0" + deflateSync(Buffer.from(json, "utf8")).toString("base64");

console.error("JSON:", json);
console.log(str);
