#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${SOURCEMOD_ARTIFACT_DIR:-$ROOT_DIR/dist/sourcemod/artifact}"

if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "SourceMod artifact directory not found at $ARTIFACT_DIR" >&2
  exit 1
fi

python3 - "$ROOT_DIR" "$ARTIFACT_DIR" <<'PY'
import json
import os
import sys


def assert_exists(path: str) -> None:
  if not os.path.exists(path):
    raise SystemExit(f"Missing artifact path: {path}")


def validate_manifest_tree(source_root: str, artifact_root: str, manifest: dict) -> None:
  if manifest.get("all", False):
    assert_exists(artifact_root)
    for entry in os.listdir(source_root):
      assert_exists(os.path.join(artifact_root, entry))

  for relative_file in manifest.get("files", []):
    assert_exists(os.path.join(artifact_root, relative_file))

  for relative_dir in manifest.get("dirs", []):
    assert_exists(os.path.join(artifact_root, relative_dir))

  for key, value in manifest.items():
    if key in {"all", "files", "dirs"}:
      continue
    if isinstance(value, dict):
      validate_manifest_tree(os.path.join(source_root, key), os.path.join(artifact_root, key), value)


root_dir, artifact_dir = sys.argv[1], sys.argv[2]

with open(os.path.join(root_dir, "plugin-package-map.json"), "r", encoding="utf-8") as fh:
  manifest = json.load(fh)

build_plugins = manifest.get("build", {}).get("plugins", {})
for bucket, plugins in build_plugins.items():
  for plugin in plugins:
    if bucket == "root":
      plugin_path = os.path.join(artifact_dir, "addons", "sourcemod", "plugins", f"{plugin}.smx")
    else:
      plugin_path = os.path.join(artifact_dir, "addons", "sourcemod", "plugins", bucket, f"{plugin}.smx")
    assert_exists(plugin_path)

source_root = os.path.join(root_dir, "addons", "sourcemod")
artifact_root = os.path.join(artifact_dir, "addons", "sourcemod")
artifact_manifest = manifest.get("artifact", {}).get("addons", {}).get("sourcemod", {})
validate_manifest_tree(source_root, artifact_root, artifact_manifest)

for forbidden in (
  os.path.join(artifact_root, "plugins", "lilac_sourcetv_test.smx"),
  os.path.join(artifact_root, "scripting", "lilac_sourcetv_test.sp"),
  os.path.join(artifact_root, "scripting", "include", "lilac.inc"),
  os.path.join(artifact_root, "scripting", "include", "colors.inc"),
):
  if os.path.exists(forbidden):
    raise SystemExit(f"Forbidden artifact path: {forbidden}")

include_dir = os.path.join(artifact_root, "scripting", "include")
include_entries = sorted(
  entry for entry in os.listdir(include_dir)
  if os.path.isfile(os.path.join(include_dir, entry))
)
if include_entries != ["lilac_sourcetv.inc"]:
  raise SystemExit(f"Unexpected public includes: {include_entries}")

for path in (
  os.path.join(artifact_dir, "README.md"),
  os.path.join(artifact_dir, "LICENSE"),
  os.path.join(artifact_dir, "Changelog"),
  os.path.join(artifact_dir, "plugin-package-map.json"),
  os.path.join(artifact_dir, "compile.log"),
):
  assert_exists(path)

print("ARTIFACT_VALIDATION_OK")
PY
