#!/usr/bin/env python3

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path


def get_build_plugin_buckets(manifest: dict) -> dict:
  return manifest.get("build", {}).get("plugins", {})


def classify_plugin(plugin_stem: str, build_buckets: dict) -> str | None:
  for bucket, plugins in build_buckets.items():
    if plugin_stem in plugins:
      return bucket
  return None


def run_spcomp(spcomp: Path, source_file: Path, include_dirs: list[Path], output_file: Path, compile_log: Path) -> None:
  cmd = [str(spcomp), str(source_file)]
  for include_dir in include_dirs:
    cmd.append(f"-i{include_dir}")
  cmd.append(f"-o{output_file}")

  rel_output = output_file.as_posix().split("/addons/", 1)[-1]
  print(f"Compiling {source_file.name} -> addons/{rel_output}", flush=True)
  result = subprocess.run(cmd, capture_output=True, text=True, check=False)

  if result.stdout:
    print(result.stdout, end="")
  if result.stderr:
    print(result.stderr, end="", file=sys.stderr)

  with compile_log.open("a", encoding="utf-8", newline="") as fh:
    if result.stdout:
      fh.write(result.stdout)
    if result.stderr:
      fh.write(result.stderr)

  if result.returncode != 0:
    raise RuntimeError(f"spcomp failed for {source_file.name}")

  if not output_file.exists():
    raise RuntimeError(f"Expected output file was not generated: {output_file}")


def remove_tree_if_exists(target: Path) -> None:
  if not target.exists():
    return

  last_error = None
  for _ in range(3):
    try:
      shutil.rmtree(target)
      return
    except FileNotFoundError:
      return
    except OSError as exc:
      last_error = exc
      time.sleep(0.2)

  if target.exists() and last_error is not None:
    raise last_error


def detect_default_workspace(root: Path) -> Path | None:
  if root.as_posix().startswith("/mnt/"):
    return Path("/tmp/lilac-sourcetv-build")
  return None


def copy_selected_files(source_root: Path, target_root: Path, files: list[str]) -> None:
  if not files:
    return
  target_root.mkdir(parents=True, exist_ok=True)
  for relative_file in files:
    source_file = source_root / relative_file
    target_file = target_root / relative_file
    if not source_file.exists():
      raise FileNotFoundError(f"Required artifact file not found: {source_file}")
    target_file.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_file, target_file)


def copy_selected_directories(source_root: Path, target_root: Path, directories: list[str]) -> None:
  if not directories:
    return
  target_root.mkdir(parents=True, exist_ok=True)
  for relative_dir in directories:
    source_dir = source_root / relative_dir
    target_dir = target_root / relative_dir
    if not source_dir.exists():
      raise FileNotFoundError(f"Required artifact directory not found: {source_dir}")
    shutil.copytree(source_dir, target_dir, dirs_exist_ok=True)


def copy_all_children(source_root: Path, target_root: Path) -> None:
  if not source_root.exists():
    raise FileNotFoundError(f"Required artifact source not found: {source_root}")
  target_root.mkdir(parents=True, exist_ok=True)
  for entry in source_root.iterdir():
    destination = target_root / entry.name
    if entry.is_dir():
      shutil.copytree(entry, destination, dirs_exist_ok=True)
    else:
      shutil.copy2(entry, destination)


def copy_manifest_tree(manifest: dict, source_root: Path, target_root: Path) -> None:
  if manifest.get("all", False):
    copy_all_children(source_root, target_root)

  files = manifest.get("files", [])
  if files:
    copy_selected_files(source_root, target_root, files)

  directories = manifest.get("dirs", [])
  if directories:
    copy_selected_directories(source_root, target_root, directories)

  for key, value in manifest.items():
    if key in {"all", "files", "dirs"}:
      continue
    if isinstance(value, dict):
      copy_manifest_tree(value, source_root / key, target_root / key)


def main() -> int:
  parser = argparse.ArgumentParser(description="Compile Lilac-SourceTV SourceMod plugins into a local build directory.")
  parser.add_argument("--root", default=".", help="Repository root")
  parser.add_argument("--spcomp", required=True, help="Path to spcomp executable")
  parser.add_argument("--output-root", default="build", help="Output directory relative to repo root")
  parser.add_argument("--compile-log", required=True, help="Compile log path relative to repo root")
  parser.add_argument("--workspace", default="", help="Optional temporary workspace directory")
  args = parser.parse_args()

  root = Path(args.root).resolve()
  spcomp = Path(args.spcomp).resolve()
  output_root = (root / args.output_root).resolve()
  compile_log = (root / args.compile_log).resolve()
  workspace = Path(args.workspace).resolve() if args.workspace else detect_default_workspace(root)

  if not spcomp.exists():
    raise FileNotFoundError(f"spcomp not found: {spcomp}")
  spcomp.chmod(spcomp.stat().st_mode | 0o111)

  source_mod_include_dir = spcomp.parent / "include"
  if not source_mod_include_dir.exists():
    raise FileNotFoundError(f"SourceMod include dir not found: {source_mod_include_dir}")

  package_map_path = root / "plugin-package-map.json"
  if not package_map_path.exists():
    raise FileNotFoundError(f"plugin-package-map.json not found: {package_map_path}")

  with package_map_path.open("r", encoding="utf-8") as fh:
    manifest = json.load(fh)

  build_buckets = get_build_plugin_buckets(manifest)
  artifact_manifest = manifest.get("artifact", {}).get("addons", {}).get("sourcemod", {})

  source_root = root / "addons" / "sourcemod"
  scripting_dir = source_root / "scripting"
  include_dir = scripting_dir / "include"

  if workspace is not None:
    print(f"Using temporary workspace: {workspace}", flush=True)
    remove_tree_if_exists(workspace)
    workspace.mkdir(parents=True, exist_ok=True)
    workspace_source_root = workspace / "addons" / "sourcemod"
    shutil.copytree(source_root, workspace_source_root, dirs_exist_ok=True)
    workspace_spcomp_dir = workspace / "spcomp"
    workspace_spcomp_dir.mkdir(parents=True, exist_ok=True)
    workspace_spcomp = workspace_spcomp_dir / spcomp.name
    shutil.copy2(spcomp, workspace_spcomp)
    workspace_spcomp.chmod(workspace_spcomp.stat().st_mode | 0o111)
    shutil.copytree(source_mod_include_dir, workspace_spcomp_dir / "include", dirs_exist_ok=True)
    source_root = workspace_source_root
    scripting_dir = source_root / "scripting"
    include_dir = scripting_dir / "include"
    spcomp = workspace_spcomp
    source_mod_include_dir = workspace_spcomp_dir / "include"

  artifact_root = output_root / "addons" / "sourcemod"
  plugins_root = artifact_root / "plugins"
  remove_tree_if_exists(output_root)
  plugins_root.mkdir(parents=True, exist_ok=True)
  for bucket in build_buckets:
    if bucket != "root":
      (plugins_root / bucket).mkdir(parents=True, exist_ok=True)

  compile_log.parent.mkdir(parents=True, exist_ok=True)
  compile_log.write_text("", encoding="utf-8")

  include_dirs = [include_dir, scripting_dir, source_mod_include_dir]
  plugin_sources = sorted(scripting_dir.glob("*.sp"))
  if not plugin_sources:
    raise RuntimeError(f"No plugin sources found in {scripting_dir}")

  for source_file in plugin_sources:
    plugin_stem = source_file.stem
    bucket = classify_plugin(plugin_stem, build_buckets)
    if bucket is None:
      print(f"Skipping {source_file.name}: no plugin bucket mapping", flush=True)
      continue
    if bucket == "root":
      output_file = plugins_root / f"{plugin_stem}.smx"
    else:
      output_file = plugins_root / bucket / f"{plugin_stem}.smx"
    run_spcomp(spcomp, source_file, include_dirs, output_file, compile_log)

  copy_manifest_tree(artifact_manifest, source_root, artifact_root)

  if workspace is not None and workspace.exists():
    remove_tree_if_exists(workspace)

  print()
  print(f"Build local completed in: {output_root}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
