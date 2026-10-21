#!/usr/bin/env python3
"""Fast checks of release tooling contracts, without launching the game."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load("check")
export = load("export_release")


class ReleaseContracts(unittest.TestCase):
    def test_false_success_is_rejected(self):
        self.assertTrue(check.output_passed(0, "INPUT ACTIONS: 25 checks, 0 failures", None))
        self.assertFalse(check.output_passed(0, "INPUT ACTIONS: 0 checks, 0 failures\nSCRIPT ERROR: missing type", None))
        self.assertFalse(check.output_passed(0, "INPUT ACTIONS: 0 checks, 0 failures", "INPUT ACTIONS:"))
        self.assertFalse(check.output_passed(0, "INPUT ACTIONS: 25 checks, 2 failures", "INPUT ACTIONS:"))
        self.assertFalse(check.output_passed(1, "INPUT ACTIONS: 25 checks, 0 failures", None))
        self.assertFalse(check.output_passed(None, "INPUT ACTIONS: PASS\nTIMEOUT", None))
        self.assertFalse(check.output_passed(0, "Godot initialized", None))

    def test_every_test_is_accounted_for(self):
        registered = {script for entries in check.GROUPS.values() for script, _ in entries}
        self.assertTrue({p.name for p in (ROOT / "tests").glob("test_*.gd")} <= registered)
        default = {row[1] for row in check.selected_suites(check.DEFAULT_GROUPS, [])}
        self.assertIn("test_hull_regroup.gd", default)
        self.assertIn("test_input_actions.gd", default)
        self.assertNotIn("test_cover_search_cost.gd", default)
        self.assertIn("test_cover_search_cost.gd", {x[0] for x in check.GROUPS["performance"]})

    def test_staging_contains_runtime_data_without_dev_files(self):
        metadata = {"version":"0.1.0-test", "commit":"test-stamp"}
        original = (ROOT / "resources/build_info.json").read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "project"
            stage.mkdir()
            export.stage_project(stage, metadata, Path(directory) / "templates")
            for name in ("scenarios.json", "units.json", "field_units.json", "combat.json", "city_building_geometry.json"):
                self.assertEqual((stage / "resources" / name).read_bytes(), (ROOT / "resources" / name).read_bytes())
            self.assertIn("test-stamp", (stage / "resources/build_info.json").read_text())
            self.assertIn('config/version="0.1.0-test"', (stage / "project.godot").read_text())
            self.assertIn("resources/*.json", (stage / "export_presets.cfg").read_text())
            self.assertNotIn("tests", {p.name for p in stage.iterdir()})
            self.assertFalse((stage / ".git").exists())
            self.assertFalse((stage / ".godot").exists())
        self.assertEqual(original, (ROOT / "resources/build_info.json").read_bytes())

    def test_universal_mac_staging_has_both_texture_imports_and_template_channels(self):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "project"
            stage.mkdir()
            export.stage_project(stage, {"version":"0.2.1-playtest"}, Path(directory) / "templates", macos=True)
            project = (stage / "project.godot").read_text()
            self.assertIn("textures/vram_compression/import_etc2_astc=true", project)
            self.assertIn("textures/vram_compression/import_s3tc_bptc=true", project)
            mac = (stage / "export_presets.cfg").read_text().split("[preset.2.options]", 1)[1]
            self.assertIn('application/short_version="0.2.1"', mac)
            self.assertIn('application/version="0.2.1"', mac)
            self.assertRegex(mac, r'custom_template/debug="[^"]*/templates/macos.zip"')
            self.assertRegex(mac, r'custom_template/release="[^"]*/templates/macos.zip"')

    def test_version_cannot_escape_artifact_directory(self):
        with self.assertRaises(ValueError):
            export.build_metadata("../../outside")

    def test_dirty_source_ignores_only_derived_untracked_godot_sidecars(self):
        tracked = {"scripts/battle.gd", "shaders/effect.gdshader", "assets/material.png"}
        generated = ["scripts/battle.gd.uid", "shaders/effect.gdshader.uid", "assets/material.png.import"]
        self.assertFalse(export.meaningful_dirty(False, generated, tracked))
        self.assertFalse(export.meaningful_dirty(False, [], tracked))
        self.assertTrue(export.meaningful_dirty(True, generated, tracked), "any tracked edit, including metadata, must count")
        self.assertFalse(export.meaningful_dirty(False, [*generated, "artifacts/test.png.import"], tracked, {"artifacts/test.png"}))
        self.assertTrue(export.meaningful_dirty(False, [*generated, "artifacts/not-ignored.png.import"], tracked))
        for new_file in ("scripts/new.gd", "assets/new.png", "docs/new.md", "scripts/orphan.gd.uid", "assets/orphan.png.import"):
            with self.subTest(new_file=new_file):
                self.assertTrue(export.meaningful_dirty(False, [*generated, new_file], tracked))

    def test_dirty_source_reads_git_status_without_hiding_real_edits(self):
        original_root = export.ROOT
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            def git(*arguments):
                subprocess.run(["git", "-C", str(repo), *arguments], check=True, capture_output=True)
            git("init", "--quiet")
            (repo / "scripts").mkdir()
            (repo / "artifacts").mkdir()
            (repo / "hooks").mkdir()
            (repo / ".gitignore").write_text("artifacts/*.png\n")
            source = repo / "scripts/battle.gd"
            source.write_text("extends RefCounted\n")
            git("add", ".gitignore", "scripts/battle.gd")
            git("-c", "user.name=Release tooling test", "-c", "user.email=test@example.invalid",
                "-c", "core.hooksPath=" + str(repo / "hooks"), "-c", "commit.gpgsign=false",
                "commit", "--quiet", "-m", "Fixture")
            try:
                export.ROOT = repo
                self.assertFalse(export.source_is_dirty())
                (repo / "scripts/battle.gd.uid").write_text("uid://fixture\n")
                (repo / "artifacts/test.png").write_bytes(b"fixture")
                (repo / "artifacts/test.png.import").write_text("generated import\n")
                self.assertFalse(export.source_is_dirty(), "derived metadata must not dirty a source-clean checkout")
                new_source = repo / "scripts/new.gd"
                new_source.write_text("extends RefCounted\n")
                self.assertTrue(export.source_is_dirty(), "new source must still count")
                new_source.unlink()
                source.write_text("extends Node\n")
                self.assertTrue(export.source_is_dirty(), "tracked source edits must still count")
            finally:
                export.ROOT = original_root


if __name__ == "__main__":
    unittest.main()
