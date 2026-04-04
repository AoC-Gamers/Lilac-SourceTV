#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-}"
OUTPUT_PATH="${2:-}"
CHANGELOG_PATH="${3:-Changelog}"

if [[ -z "$VERSION" || -z "$OUTPUT_PATH" ]]; then
	echo "Usage: $0 <version> <output-path> [changelog-path]" >&2
	exit 1
fi

if [[ ! -f "$CHANGELOG_PATH" ]]; then
	echo "Changelog not found at $CHANGELOG_PATH" >&2
	exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

awk -v version="$VERSION" '
	BEGIN {
		in_section = 0
		found = 0
	}
	$0 ~ "^##[[:space:]]+" version "([[:space:]]+-.*)?$" {
		in_section = 1
		found = 1
		next
	}
	$0 ~ "^##[[:space:]]+" && in_section {
		exit
	}
	in_section {
		print
	}
	END {
		if (!found) {
			exit 2
		}
	}
' "$CHANGELOG_PATH" > "$OUTPUT_PATH"

python3 - "$OUTPUT_PATH" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
content = content.strip()
if not content:
    raise SystemExit("Release notes section is empty")
path.write_text(content + "\n", encoding="utf-8")
PY
