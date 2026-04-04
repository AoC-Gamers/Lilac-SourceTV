#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${SOURCEMOD_ARTIFACT_DIR:-$ROOT_DIR/dist/sourcemod/artifact}"

if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "SourceMod artifact directory not found at $ARTIFACT_DIR" >&2
  exit 1
fi

python3 - "$ARTIFACT_DIR" <<'PY'
import os
import sys

artifact_dir = sys.argv[1]
sm_dir = os.path.join(artifact_dir, "addons", "sourcemod")

expected_files = [
    os.path.join(sm_dir, "plugins", "lilac_sourcetv.smx"),
    os.path.join(sm_dir, "scripting", "lilac_sourcetv.sp"),
    os.path.join(sm_dir, "scripting", "include", "lilac_sourcetv.inc"),
    os.path.join(sm_dir, "translations", "lilac_sourcetv.phrases.txt"),
    os.path.join(artifact_dir, "compile.log"),
]

for path in expected_files:
    if not os.path.isfile(path):
        raise SystemExit(f"Missing artifact file: {path}")

for forbidden in [
    os.path.join(sm_dir, "plugins", "lilac_sourcetv_test.smx"),
    os.path.join(sm_dir, "scripting", "lilac_sourcetv_test.sp"),
    os.path.join(sm_dir, "scripting", "include", "lilac.inc"),
]:
    if os.path.exists(forbidden):
        raise SystemExit(f"Forbidden artifact file: {forbidden}")

include_dir = os.path.join(sm_dir, "scripting", "include")
include_entries = sorted(
    entry for entry in os.listdir(include_dir)
    if os.path.isfile(os.path.join(include_dir, entry))
)
if include_entries != ["lilac_sourcetv.inc"]:
    raise SystemExit(f"Unexpected public includes: {include_entries}")

print("ARTIFACT_VALIDATION_OK")
PY
