#!/usr/bin/env python3
"""Build standalone playtest candidates from an isolated, stamped staging copy.

No upload/publish step. Example:
GODOT_BIN=/path/to/godot python3 tools/export_release.py --platform linux \
    --templates-dir /path/to/4.5.1.stable --smoke
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
RUNTIME_DIRECTORIES = ("assets", "resources", "scenes", "scripts", "shaders")
TARGETS = {
    "linux": (0, "Linux x86_64", "linux_release.x86_64", "RA-Neo.x86_64"),
    "windows": (1, "Windows x86_64", "windows_release_x86_64.exe", "RA-Neo.exe"),
    "macos": (2, "macOS universal", "macos.zip", "RA-Neo.zip"),
}


def git(*arguments):
    result = subprocess.run(["git", "-C", str(ROOT), *arguments], text=True, capture_output=True)
    return result.stdout.rstrip("\r\n") if result.returncode == 0 else ""


def sidecar_source(path):
    if path.endswith((".gd.uid", ".gdshader.uid")):
        return path[:-4]
    if path.endswith(".import"):
        return path[:-7]
    return None


def meaningful_dirty(tracked_changed, untracked, tracked, ignored_artifacts=()):
    """Ignore only untracked Godot sidecars derived from already tracked inputs.

    Tracked sidecar edits still count. A new source/asset or an orphan sidecar
    still counts. This does not hide any source through a broad ignore rule.
    """
    if tracked_changed:
        return True
    for path in untracked:
        source = sidecar_source(path)
        if source not in tracked and source not in ignored_artifacts:
            return True
    return False


def source_is_dirty():
    tracked_changed = bool(git("status", "--porcelain", "--untracked-files=no"))
    tracked = set(filter(None, git("ls-files", "-z").split("\0")))
    untracked = list(filter(None, git("ls-files", "--others", "--exclude-standard", "-z").split("\0")))
    # A later editor import can also create .import files for ignored test
    # screenshots. Ignore these only when Git itself ignores their source
    # under artifacts/, which is never part of the runtime export.
    artifact_sources = {source for path in untracked
                        if (source := sidecar_source(path)) and source.startswith("artifacts/")}
    ignored_artifacts = set()
    if artifact_sources:
        result = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--stdin", "-z"],
                                input="\0".join(artifact_sources) + "\0", text=True, capture_output=True)
        if result.returncode in (0, 1):
            ignored_artifacts = set(filter(None, result.stdout.split("\0")))
    return meaningful_dirty(tracked_changed, untracked, tracked, ignored_artifacts)


def build_metadata(version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("Version must be x.y.z or x.y.z-playtest")
    commit = git("rev-parse", "HEAD") or "unknown"
    return {"version": version, "commit": commit, "engine": "4.5.1", "channel": "playtest-candidate",
            "dirty": source_is_dirty(),
            "built_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds")}


def stage_project(stage, metadata, templates, macos=False):
    for name in RUNTIME_DIRECTORIES:
        shutil.copytree(ROOT / name, stage / name)
    project = (ROOT / "project.godot").read_text()
    version_setting = "config/version=" + json.dumps(metadata["version"])
    if re.search(r"(?m)^config/version=.*$", project):
        project = re.sub(r"(?m)^config/version=.*$", version_setting, project)
    else:
        project = project.replace("[application]", "[application]\n" + version_setting)
    if macos:
        # Universal Mac templates require ARM texture imports as well as desktop imports.
        for key in ("import_etc2_astc", "import_s3tc_bptc"):
            pattern = rf"(?m)^textures/vram_compression/{key}=.*$"
            setting = f"textures/vram_compression/{key}=true"
            if re.search(pattern, project):
                project = re.sub(pattern, setting, project)
            else:
                project = project.replace("[rendering]", "[rendering]\n" + setting)
    (stage / "project.godot").write_text(project)
    presets = (ROOT / "export_presets.cfg").read_text()
    numeric_version = metadata["version"].split("-", 1)[0]
    for key in ("short_version", "version"):
        presets = re.sub(rf'(?m)^application/{key}=.*$',
                         f'application/{key}="{numeric_version}"', presets)
    if templates is not None:
        # Presets keep portable defaults in Git; only this temporary copy gets absolute paths.
        for index, _, template, _ in TARGETS.values():
            section = f"[preset.{index}.options]"
            start = presets.index(section)
            next_section = presets.find("\n[preset.", start + len(section))
            end = len(presets) if next_section < 0 else next_section
            body = presets[start:end].replace('custom_template/release=""',
                                               "custom_template/release=" + json.dumps(str(templates / template)))
            if index == 2:
                # Mac validates both channels; its archive contains both executables.
                body = body.replace('custom_template/debug=""', "custom_template/debug=" + json.dumps(str(templates / template)))
            presets = presets[:start] + body + presets[end:]
    (stage / "export_presets.cfg").write_text(presets)
    (stage / "resources" / "build_info.json").write_text(json.dumps(metadata, indent=2) + "\n")


def run(command, environment, log, timeout=300):
    result = subprocess.run(command, text=True, capture_output=True, env=environment, timeout=timeout)
    output = result.stdout + result.stderr
    log.write_text(output)
    if result.returncode or "SCRIPT ERROR" in output or "Failed to export" in output:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}\n{output[-5000:]}")
    return output


def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=(*TARGETS, "all"), default="linux")
    parser.add_argument("--templates-dir", type=Path, help="Folder containing official 4.5.1.stable templates")
    parser.add_argument("--output", type=Path, default=ROOT / "builds")
    parser.add_argument("--version", default=json.loads((ROOT / "resources/build_info.json").read_text())["version"])
    parser.add_argument("--smoke", action="store_true", help="Run the exported Linux binary headlessly (not native graphics QA)")
    parser.add_argument("--keep-staging", action="store_true", help="Keep the staging directory for diagnosing an export")
    args = parser.parse_args(argv)
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not engine and Path("/Applications/Godot.app/Contents/MacOS/Godot").is_file():
        engine = "/Applications/Godot.app/Contents/MacOS/Godot"
    if not engine:
        parser.error("Set GODOT_BIN to Godot 4.5.1")
    actual_version = subprocess.check_output([engine, "--version"], text=True).strip()
    if not actual_version.startswith("4.5.1."):
        parser.error(f"Expected Godot 4.5.1, found {actual_version}")
    platforms = list(TARGETS) if args.platform == "all" else [args.platform]
    if args.smoke and ("linux" not in platforms or not sys.platform.startswith("linux")):
        parser.error("--smoke runs a Linux export on Linux; other target OS checks remain manual")
    templates = args.templates_dir.resolve() if args.templates_dir else None
    if templates is None:
        if sys.platform == "darwin":
            templates = Path.home() / "Library/Application Support/Godot/export_templates/4.5.1.stable"
        elif sys.platform == "win32":
            templates = Path(os.environ.get("APPDATA", str(Path.home()))) / "Godot/export_templates/4.5.1.stable"
        else:
            templates = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot/export_templates/4.5.1.stable"
    if templates is not None:
        for platform in platforms:
            if not (templates / TARGETS[platform][2]).is_file():
                parser.error(f"Missing template: {templates / TARGETS[platform][2]}")
        version_file = templates / "version.txt"
        if version_file.is_file() and version_file.read_text().strip() != "4.5.1.stable":
            parser.error("Template version.txt does not match 4.5.1.stable")
    try:
        metadata = build_metadata(args.version)
    except ValueError as error:
        parser.error(str(error))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="ra-neo-export-"))
    stage = work / "project"
    stage.mkdir()
    environment = os.environ.copy()
    for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        (work / name).mkdir()
        environment[key] = str(work / name)
    try:
        stage_project(stage, metadata, templates, macos="macos" in platforms)
        run([engine, "--headless", "--editor", "--path", str(stage), "--log-file", str(work / "import-engine.log"), "--import"],
            environment, work / "import.log")
        for platform in platforms:
            _, preset, _, executable = TARGETS[platform]
            folder = output / f"ra-neo-{args.version}-{metadata['commit'][:8]}-{platform}"
            # Never mix an older candidate's files or evidence into a new build.
            # A deliberate rerun chooses a fresh --output directory.
            if folder.exists():
                raise RuntimeError(f"Candidate folder already exists: {folder}; choose a fresh --output directory")
            folder.mkdir(parents=True)
            target = folder / executable
            run([engine, "--headless", "--path", str(stage), "--log-file", str(folder / "export-engine.log"),
                 "--export-release", preset, str(target)], environment, folder / "export.log")
            if not target.is_file() or target.stat().st_size < 1024:
                raise RuntimeError(f"Exporter did not create {target}")
            run([engine, "--headless", "--path", str(stage), "--log-file", str(work / "notices-engine.log"),
                 "--script", str(ROOT / "tools/write_engine_notices.gd"), "--", "--output=" + str(folder)],
                environment, work / "notices.log")
            shutil.copy2(ROOT / "docs/playtest-readme.txt", folder / "README.txt")
            shutil.copy2(ROOT / "assets/materials/README.md", folder / "MATERIAL-PROVENANCE.md")
            validation = {"exported": True, "linux_headless_startup": False, "native_target_os_tested": False,
                          "signed_for_public_distribution": False}
            if args.smoke and platform == "linux":
                target.chmod(target.stat().st_mode | 0o111)
                run([str(target), "--headless", "--audio-driver", "Dummy", "--quit-after", "3",
                     "--log-file", str(folder / "smoke-engine.log")], environment, folder / "smoke.log", timeout=120)
                validation["linux_headless_startup"] = True
            files = {path.name: {"bytes":path.stat().st_size, "sha256":digest(path)} for path in folder.iterdir()
                     if path.is_file() and path.suffix != ".log" and path.name != "build-manifest.json"}
            manifest = {**metadata, "target": platform, "actual_engine": actual_version,
                        "scenario_sha256": digest(stage / "resources/scenarios.json"),
                        "validation": validation, "files": files}
            (folder / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
            archive = shutil.make_archive(str(folder), "zip", root_dir=folder)
            print(f"EXPORT: {platform}: {archive}")
            print(f"  startup smoke: {validation['linux_headless_startup']}; native OS acceptance: pending")
        return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"EXPORT FAILED: {error}\nStaging preserved: {work}", file=sys.stderr)
        args.keep_staging = True
        return 1
    finally:
        if args.keep_staging:
            print(f"STAGING: {work}")
        else:
            shutil.rmtree(work)


if __name__ == "__main__":
    sys.exit(main())
