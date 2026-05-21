#!/usr/bin/env bash

set -euo pipefail

: "${RELEASE_BASENAME:?RELEASE_BASENAME is required}"

python3 ./scripts/package-release.py --root . --basename "$RELEASE_BASENAME"
