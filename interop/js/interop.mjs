import { encode, decode, Tag } from "cbor2";
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "fs";

const testValues = {
  int_zero: 0,
  int_small: 23,
  int_u8: 200,
  int_u16: 1000,
  int_u32: 1_000_000,
  int_neg_small: -10,
  int_neg_500: -500,
  float_1_5: 1.5,
  float_neg: -273.15,
  string_empty: "",
  string_hello: "hello",
  bytes_empty: new Uint8Array([]),
  bytes_small: new Uint8Array([1, 2, 3, 4, 5]),
  bool_true: true,
  bool_false: false,
  null: null,
  array_ints: [1, 2, 3],
  array_empty: [],
  array_strings: ["hello", "world"],
  array_nested: [[1, 2], [3, 4]],
  map_simple: new Map([["a", 1], ["b", 2]]),
  map_empty: new Map(),
  map_nested: new Map([["outer", new Map([["inner", 42]])]]),
  map_array_vals: new Map([["nums", [1, 2, 3]]]),
  tag_epoch: new Tag(1, 1_000_000),
  tag_uri: new Tag(32, "https://example.com"),
  tag_array: new Tag(1000, [1, 2, 3]),
};

function generate(dir) {
  mkdirSync(dir, { recursive: true });
  for (const [name, value] of Object.entries(testValues)) {
    const buf = encode(value);
    writeFileSync(`${dir}/${name}.cbor`, buf);
  }
  console.log(`  Generated fixtures in ${dir}/`);
}

function deepEqual(a, b) {
  if (a === b) return true;
  if (a === null || b === null) return a === b;

  // Handle Tag (some decoders auto-convert Tag 1 to Date, Tag 32 to URL)
  if (a instanceof Tag && b instanceof Tag) {
    return a.tag === b.tag && deepEqual(a.contents, b.contents);
  }
  if (a instanceof Date && b instanceof Tag && b.tag === 1) {
    return a.getTime() === b.contents * 1000;
  }
  if (typeof a === "string" && b instanceof Tag && b.tag === 1) {
    return new Date(a).getTime() === b.contents * 1000;
  }
  // cbor2 auto-converts Tag 32 (URI) to URL object
  if (a instanceof URL && b instanceof Tag && b.tag === 32) {
    return a.href === b.contents || a.href === b.contents + "/";
  }

  if (typeof a !== typeof b) return false;

  // Handle Uint8Array / Buffer
  if (a instanceof Uint8Array && b instanceof Uint8Array) {
    if (a.length !== b.length) return false;
    return a.every((v, i) => v === b[i]);
  }

  // Handle Map
  if (a instanceof Map && b instanceof Map) {
    if (a.size !== b.size) return false;
    for (const [k, v] of a) {
      if (!b.has(k) || !deepEqual(b.get(k), v)) return false;
    }
    return true;
  }

  // Handle Array
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((v, i) => deepEqual(v, b[i]));
  }

  return false;
}

// Recursively convert plain objects to Maps so we can compare across languages.
// cbor2's decode already returns Maps, but other encoders (Python, Gleam) may
// produce plain-object representations depending on the decoder.
function toMapsDeep(val, name) {
  if (val === null || val === undefined) return val;
  if (val instanceof Tag) return val;
  if (val instanceof Map) {
    const m = new Map();
    for (const [k, v] of val) m.set(k, toMapsDeep(v, name));
    return m;
  }
  if (Array.isArray(val)) return val.map((v) => toMapsDeep(v, name));
  if (val instanceof URL) return val;
  if (typeof val === "object" && !(val instanceof Uint8Array) && !(val instanceof Date)) {
    const m = new Map();
    for (const [k, v] of Object.entries(val)) m.set(k, toMapsDeep(v, name));
    return m;
  }
  return val;
}

function verify(dir, source) {
  if (!existsSync(dir)) {
    console.error(`  Skipping ${source} fixtures (not found: ${dir})`);
    return;
  }

  let passed = 0;
  let failed = 0;

  for (const [name, expected] of Object.entries(testValues)) {
    const path = `${dir}/${name}.cbor`;
    if (!existsSync(path)) {
      console.error(`  SKIP ${name}: file not found`);
      continue;
    }
    const buf = readFileSync(path);
    let decoded;
    try {
      decoded = decode(buf);
    } catch (e) {
      console.error(`  FAIL ${name}: decode error: ${e.message}`);
      failed++;
      continue;
    }

    // Other languages may encode maps as plain objects; recursively convert for comparison
    let actual = toMapsDeep(decoded, name);

    if (deepEqual(actual, expected)) {
      passed++;
    } else {
      console.error(`  FAIL ${name}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(decoded)}`);
      failed++;
    }
  }

  console.log(`  Verified ${source} fixtures: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

const command = process.argv[2];
const dir = process.argv[3];
const source = process.argv[4] || dir;

switch (command) {
  case "generate":
    generate(dir || "fixtures/js");
    break;
  case "verify":
    if (!dir) { console.error("usage: verify <dir> [source]"); process.exit(1); }
    verify(dir, source);
    break;
  default:
    console.error("Usage: node interop.mjs <generate|verify> [dir] [source]");
    process.exit(1);
}
