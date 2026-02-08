#!/usr/bin/env python3
"""CBOR interop test: generate and verify fixtures using Python cbor2."""

import sys
import os
import datetime
import cbor2
from cbor2 import CBORTag

TEST_VALUES = {
    "int_zero": 0,
    "int_small": 23,
    "int_u8": 200,
    "int_u16": 1000,
    "int_u32": 1_000_000,
    "int_neg_small": -10,
    "int_neg_500": -500,
    "float_1_5": 1.5,
    "float_neg": -273.15,
    "string_empty": "",
    "string_hello": "hello",
    "bytes_empty": b"",
    "bytes_small": b"\x01\x02\x03\x04\x05",
    "bool_true": True,
    "bool_false": False,
    "null": None,
    "array_ints": [1, 2, 3],
    "array_empty": [],
    "array_strings": ["hello", "world"],
    "array_nested": [[1, 2], [3, 4]],
    "map_simple": {"a": 1, "b": 2},
    "map_empty": {},
    "map_nested": {"outer": {"inner": 42}},
    "map_array_vals": {"nums": [1, 2, 3]},
    "tag_epoch": CBORTag(1, 1_000_000),
    "tag_uri": CBORTag(32, "https://example.com"),
    "tag_array": CBORTag(1000, [1, 2, 3]),
}


def generate(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, value in TEST_VALUES.items():
        path = os.path.join(out_dir, f"{name}.cbor")
        with open(path, "wb") as f:
            cbor2.dump(value, f)
    print(f"  Generated fixtures in {out_dir}/")


def values_equal(a, b):
    # cbor2 auto-decodes Tag 1 to datetime; convert back for comparison
    if isinstance(a, datetime.datetime) and isinstance(b, CBORTag) and b.tag == 1:
        expected_dt = datetime.datetime.fromtimestamp(b.value, tz=datetime.timezone.utc)
        return a == expected_dt
    if isinstance(a, CBORTag) and isinstance(b, CBORTag):
        return a.tag == b.tag and values_equal(a.value, b.value)
    if isinstance(a, dict) and isinstance(b, dict):
        if len(a) != len(b):
            return False
        return all(k in b and values_equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(values_equal(x, y) for x, y in zip(a, b))
    if isinstance(a, float) and isinstance(b, float):
        return abs(a - b) < 1e-9
    return a == b


def verify(fixture_dir, source):
    if not os.path.isdir(fixture_dir):
        print(f"  Skipping {source} fixtures (not found: {fixture_dir})", file=sys.stderr)
        return

    passed = 0
    failed = 0

    for name, expected in TEST_VALUES.items():
        path = os.path.join(fixture_dir, f"{name}.cbor")
        if not os.path.exists(path):
            print(f"  SKIP {name}: file not found", file=sys.stderr)
            continue
        with open(path, "rb") as f:
            data = f.read()
        try:
            decoded = cbor2.loads(data)
        except Exception as e:
            print(f"  FAIL {name}: decode error: {e}", file=sys.stderr)
            failed += 1
            continue

        if values_equal(decoded, expected):
            passed += 1
        else:
            print(f"  FAIL {name}: expected {expected!r}, got {decoded!r}", file=sys.stderr)
            failed += 1

    print(f"  Verified {source} fixtures: {passed} passed, {failed} failed")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: interop.py <generate|verify> [dir] [source]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "generate":
        d = sys.argv[2] if len(sys.argv) > 2 else "fixtures/python"
        generate(d)
    elif cmd == "verify":
        d = sys.argv[2] if len(sys.argv) > 2 else None
        if not d:
            print("usage: verify <dir> [source]", file=sys.stderr)
            sys.exit(1)
        s = sys.argv[3] if len(sys.argv) > 3 else d
        verify(d, s)
    else:
        print("Usage: interop.py <generate|verify> [dir] [source]", file=sys.stderr)
        sys.exit(1)
