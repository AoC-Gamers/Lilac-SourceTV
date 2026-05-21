#!/usr/bin/env python3

import argparse
import shutil
from pathlib import Path


def main() -> int:
  parser = argparse.ArgumentParser(description="Package dist/sourcemod/artifact into a ZIP archive.")
  parser.add_argument("--root", default=".")
  parser.add_argument("--basename", required=True)
  args = parser.parse_args()

  root = Path(args.root).resolve()
  artifact_dir = root / "dist" / "sourcemod" / "artifact"
  release_dir = root / "dist" / "release"
  archive_base = release_dir / args.basename
  archive_path = archive_base.with_suffix(".zip")

  if not artifact_dir.exists():
    raise FileNotFoundError(f"Artifact tree not found: {artifact_dir}")

  release_dir.mkdir(parents=True, exist_ok=True)
  if archive_path.exists():
    archive_path.unlink()

  shutil.make_archive(str(archive_base), "zip", root_dir=artifact_dir)
  print(f"Release archive generated in: {archive_path}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
