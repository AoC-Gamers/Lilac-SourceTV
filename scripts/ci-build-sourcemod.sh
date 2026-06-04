#!/usr/bin/env bash

set -euo pipefail

echo "Resolving SourceMod dependencies through make..."
make deps-smx PYTHON=python3 SOURCEMOD_VERSION="${SOURCEMOD_VERSION:-1.12}" SMX_PLATFORM=linux

echo "Building SourceMod artifact through make..."
make build-smx PYTHON=python3 SPCOMP="deps/sourcemod-linux/addons/sourcemod/scripting/spcomp"

echo "Packaging SourceMod artifact through make..."
make package-smx PYTHON=python3

python3 ./scripts/stage-artifact.py . ./.build/package-smx ./deps/build-smx-compile.log
