#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"

# Python cbor2 is accessed via nix-shell
PYTHON="nix-shell -p python3Packages.cbor2 --run"

echo "=== CBOR Interop Tests ==="
echo ""

# --- Build / install ---
echo "[1/4] Building Gleam..."
cd "$PROJECT_DIR"
gleam build >/dev/null 2>&1
echo "  Done."

echo "[2/4] Installing JS dependencies (cbor2)..."
cd "$SCRIPT_DIR/js"
npm install --silent 2>&1
echo "  Done."

echo ""

# --- Generate fixtures ---
echo "[3/4] Generating fixtures..."
rm -rf "$FIXTURES"
mkdir -p "$FIXTURES"/{python,js,gleam}

$PYTHON "python3 $SCRIPT_DIR/python/interop.py generate $FIXTURES/python"
node "$SCRIPT_DIR/js/interop.mjs" generate "$FIXTURES/js"
cd "$PROJECT_DIR"
escript "$SCRIPT_DIR/gleam_interop.escript" generate "$FIXTURES/gleam"

echo ""

# --- Cross-verify ---
echo "[4/4] Cross-verifying all implementations..."
echo ""

echo "Python (cbor2) verifying others:"
$PYTHON "python3 $SCRIPT_DIR/python/interop.py verify $FIXTURES/js    'JS (cbor2)'"
$PYTHON "python3 $SCRIPT_DIR/python/interop.py verify $FIXTURES/gleam 'Gleam (gleebor)'"

echo ""

echo "JS (cbor2) verifying others:"
node "$SCRIPT_DIR/js/interop.mjs" verify "$FIXTURES/python" "Python (cbor2)"
node "$SCRIPT_DIR/js/interop.mjs" verify "$FIXTURES/gleam"  "Gleam (gleebor)"

echo ""

echo "Gleam (gleebor) verifying others:"
cd "$PROJECT_DIR"
escript "$SCRIPT_DIR/gleam_interop.escript" verify "$FIXTURES/python" "Python (cbor2)"
escript "$SCRIPT_DIR/gleam_interop.escript" verify "$FIXTURES/js"     "JS (cbor2)"

echo ""
echo "=== All interop tests passed ==="
