#!/usr/bin/env python3

import shutil
import sys
from pathlib import Path


def copy_if_exists(source: Path, destination: Path) -> None:
  if not source.exists():
    return
  if source.is_dir():
    shutil.copytree(source, destination, dirs_exist_ok=True)
  else:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def main() -> int:
  if len(sys.argv) not in (4, 5):
    raise SystemExit("Usage: stage-artifact.py <root_dir> <build_dir> <compile_log> [output_dir]")

  root_dir = Path(sys.argv[1]).resolve()
  build_dir = Path(sys.argv[2]).resolve()
  compile_log = Path(sys.argv[3]).resolve()
  output_dir = Path(sys.argv[4]).resolve() if len(sys.argv) == 5 else root_dir / "dist" / "sourcemod" / "artifact"

  if output_dir.exists():
    shutil.rmtree(output_dir)
  output_dir.mkdir(parents=True, exist_ok=True)

  copy_if_exists(build_dir / "addons", output_dir / "addons")
  copy_if_exists(root_dir / "README.md", output_dir / "README.md")
  copy_if_exists(root_dir / "LICENSE", output_dir / "LICENSE")
  copy_if_exists(root_dir / "Changelog", output_dir / "Changelog")
  copy_if_exists(root_dir / "plugin-package-map.json", output_dir / "plugin-package-map.json")
  copy_if_exists(root_dir / "docs", output_dir / "docs")
  copy_if_exists(compile_log, output_dir / "compile.log")

  print(f"SourceMod artifacts generated in {output_dir}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
