#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${RUNNER_TEMP:-$ROOT_DIR/.tmp}/sourcemod-build"
DIST_DIR="$ROOT_DIR/dist/sourcemod"
ARTIFACT_DIR="$DIST_DIR/artifact"
SOURCEMOD_ARCHIVE_URL="${SOURCEMOD_ARCHIVE_URL:?SOURCEMOD_ARCHIVE_URL is required}"

rm -rf "$WORK_DIR" "$DIST_DIR"
mkdir -p "$WORK_DIR" "$ARTIFACT_DIR"

echo "Downloading SourceMod compiler package..."
curl -fsSL "$SOURCEMOD_ARCHIVE_URL" -o "$WORK_DIR/sourcemod.tar.gz"
tar -xzf "$WORK_DIR/sourcemod.tar.gz" -C "$WORK_DIR"

SOURCEMOD_DIR="$WORK_DIR"
SPCOMP_BIN="$SOURCEMOD_DIR/addons/sourcemod/scripting/spcomp"
SOURCEMOD_INCLUDE_DIR="$SOURCEMOD_DIR/addons/sourcemod/scripting/include"
LOCAL_INCLUDE_DIR="$ROOT_DIR/addons/sourcemod/scripting/include"
PACKAGE_SM_DIR="$ARTIFACT_DIR/addons/sourcemod"
PACKAGE_PLUGIN_DIR="$PACKAGE_SM_DIR/plugins"
PACKAGE_SCRIPTING_DIR="$PACKAGE_SM_DIR/scripting"
PACKAGE_INCLUDE_DIR="$PACKAGE_SCRIPTING_DIR/include"
PACKAGE_TRANSLATIONS_DIR="$PACKAGE_SM_DIR/translations"
COMPILE_LOG="$ARTIFACT_DIR/compile.log"

mkdir -p "$PACKAGE_PLUGIN_DIR" "$PACKAGE_SCRIPTING_DIR" "$PACKAGE_INCLUDE_DIR" "$PACKAGE_TRANSLATIONS_DIR"
: > "$COMPILE_LOG"

echo "Compiling lilac_sourcetv.sp..."
"$SPCOMP_BIN" \
  "$ROOT_DIR/addons/sourcemod/scripting/lilac_sourcetv.sp" \
  -i"$LOCAL_INCLUDE_DIR" \
  -i"$SOURCEMOD_INCLUDE_DIR" \
  -o"$PACKAGE_PLUGIN_DIR/lilac_sourcetv.smx" \
  2>&1 | tee -a "$COMPILE_LOG"

if [[ ! -f "$PACKAGE_PLUGIN_DIR/lilac_sourcetv.smx" ]]; then
  echo "Compiled plugin was not generated." >&2
  exit 1
fi

cp "$ROOT_DIR/addons/sourcemod/scripting/lilac_sourcetv.sp" "$PACKAGE_SCRIPTING_DIR/"
cp "$ROOT_DIR/addons/sourcemod/scripting/include/lilac_sourcetv.inc" "$PACKAGE_INCLUDE_DIR/"
cp "$ROOT_DIR/addons/sourcemod/translations/lilac_sourcetv.phrases.txt" "$PACKAGE_TRANSLATIONS_DIR/"

for lang_dir in "$ROOT_DIR"/addons/sourcemod/translations/*; do
  if [[ -d "$lang_dir" ]] && [[ -f "$lang_dir/lilac_sourcetv.phrases.txt" ]]; then
    mkdir -p "$PACKAGE_TRANSLATIONS_DIR/$(basename "$lang_dir")"
    cp "$lang_dir/lilac_sourcetv.phrases.txt" "$PACKAGE_TRANSLATIONS_DIR/$(basename "$lang_dir")/"
  fi
done

echo "SourceMod artifacts generated in $ARTIFACT_DIR"
