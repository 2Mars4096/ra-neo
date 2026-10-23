#!/usr/bin/env python3
"""Run registered regressions serially; never turn a script error into a pass.

Default: core/combat/probes/regression functional suites. Hardware-sensitive
cover-cost and busy-combat CPU timing are explicit: --group performance. --group release selects
current Harbor/regional player-facing coverage; --group regional checks the new
battlefields and their affected integration paths; --group playthrough runs full battles.
Use --list without an installed engine. Reports/logs go into a fresh temp folder
and artifacts/checks.json. Dedicated performance results are never implied by a
functional pass; existing timing guards in mixed functional suites stay intact.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
GROUPS = {
    # Original regression set: maps, assets, navigation, UI, missions.
    'core': [('test_engineer_works.gd', 'ENGINEER WORKS:'), ('test_city_urban.gd', 'CITY URBAN:'), ('test_city_works.gd', 'CITY WORKS:'), ('test_city_collision.gd', 'CITY COLLISION TESTS:'), ('test_assets_city.gd', 'ASSETS CITY:'), ('test_harbor_layout.gd', 'HARBOR LAYOUT TESTS:'), ('test_harbor_gameplay.gd', 'HARBOR GAMEPLAY:'), ('test_harbor_visuals.gd', 'HARBOR VISUALS:'), ('test_field_ops_resume.gd', 'FIELD OPS RESUME TESTS:'), ('test_field_geometry.gd', 'FIELD GEOMETRY:'), ('test_performance_repair.gd', 'PERFORMANCE REPAIR:'), ('test_field_ops.gd', 'FIELD OPS TESTS:'), ('test_field_ops_edges.gd', 'FIELD OPS EDGE TESTS:'), ('test_field_victory.gd', 'FIELD VICTORY:'), ('test_field_ui.gd', 'FIELD UI:'), ('test_field_visuals.gd', 'FIELD VISUALS:'), ('test_minimap_background.gd', 'MINIMAP BACKGROUND:'), ('test_asset_gallery.gd', 'ASSET GALLERY UI: 0 failures'), ('test_assets_street.gd', 'ASSETS STREET:'), ('test_assets_rural.gd', 'ASSETS RURAL:'), ('test_assets_waterfront.gd', 'WATERFRONT ASSETS:'), ('test_assets_battlefield.gd', 'BATTLEFIELD ASSETS:'), ('test_asset_library.gd', 'ASSET LIBRARY:'), ('test_asset_placement.gd', 'ASSET PLACEMENT:'), ('test_asset_palette.gd', 'ASSET PALETTE:'), ('test_review_usability.gd', 'REVIEW USABILITY:'), ('test_town_land_use.gd', 'TOWN LAND USE:'), ('test_classic_navigation.gd', 'CLASSIC NAVIGATION:'), ('test_environment_variants.gd', 'ENVIRONMENT VARIANTS:'), ('test_regroup_recovery.gd', 'REGROUP RECOVERY:'), ('test_riverside_navigation.gd', 'RIVERSIDE NAVIGATION:'), ('test_scenario_dimensions.gd', 'SCENARIO DIMENSIONS:'), ('test_town_design.gd', 'TOWN DESIGN:'), ('test_scene_air_clearance.gd', 'SCENE AIR CLEARANCE:'), ('test_tactical_flexibility.gd', 'TACTICAL FLEXIBILITY:'), ('test_architectural_parcels.gd', 'ARCHITECTURAL PARCELS:'), ('test_actor_spatial.gd', 'ACTOR SPATIAL:'), ('test_material_batching.gd', 'MATERIAL BATCHING: PASS'), ('test_roadside_props.gd', 'ROADSIDE PROPS:'), ('test_gap_navigation.gd', 'GAP NAVIGATION:'), ('test_mobility.gd', 'MOBILITY:'), ('test_road_network.gd', 'ROAD NETWORK:'), ('test_road_routing.gd', 'ROAD ROUTING:'), ('test_camera_zoom.gd', 'CAMERA ZOOM:'), ('test_hud_layout.gd', 'HUD LAYOUT:'), ('test_render_interpolation.gd', 'RENDER INTERPOLATION: PASS'), ('test_cover_behavior.gd', 'COVER BEHAVIOR:'), ('test_cover_contact.gd', 'COVER CONTACT:'), ('test_spatial_targeting.gd', 'SPATIAL TARGETING:'), ('test_classic_input.gd', 'CLASSIC INPUT:'), ('classic_playthrough.gd', 'CLASSIC SEEDS: PASS'), ('test_classic.gd', 'CLASSIC TESTS:'), ('test_stances.gd', 'STANCE TESTS:'), ('test_weather.gd', 'WEATHER TESTS:'), ('test_showcase.gd', 'SHOWCASE TESTS:'), ('test_showcase_motion.gd', 'SHOWCASE MOTION:'), ('showcase_playthrough.gd', 'SHOWCASE MISSION: PASS'), ('test_vehicle_stability.gd', 'STABILITY TESTS: PASS'), ('test_combat.gd', 'COMBAT TESTS:'), ('test_simulation.gd', 'SIMULATION TESTS:'), ('test_input.gd', 'INPUT TESTS:'), ('test_clearance.gd', 'CLEARANCE TESTS:'), ('test_effects.gd', 'EFFECTS TESTS:'), ('test_tactics.gd', 'TACTICS TESTS:'), ('test_animation.gd', 'ANIMATION TESTS:'), ('test_individuals.gd', 'INDIVIDUAL TESTS:'), ('playthrough.gd', 'PLAYTHROUGH VICTORY'), ('test_scenarios.gd', 'SCENARIO TESTS: PASS')],
    # Combat realism, damage, drones, re-crew and hitch suites (2026-10-14/15).
    'combat': [('test_garrison.gd', 'GARRISON:'), ('test_garrison_fire.gd', 'GARRISON FIRE:'), ('test_wounds.gd', 'WOUNDS:'), ('test_vehicle_damage.gd', 'VEHICLE DAMAGE:'), ('test_vehicle_followups.gd', 'VEHICLE FOLLOWUPS:'), ('test_world_damage.gd', 'WORLD DAMAGE:'), ('test_bombard_feedback.gd', 'BOMBARD FEEDBACK:'), ('test_recrew.gd', 'RECREW:'), ('test_contact_drill.gd', 'CONTACT DRILL:'), ('test_soldier_targeting.gd', 'SOLDIER TARGETING:'), ('test_per_body_cover.gd', 'PER-BODY COVER:'), ('test_wave_strength.gd', 'WAVE STRENGTH:'), ('test_enemy_defences.gd', 'ENEMY DEFENCES:'), ('test_counter_drone.gd', 'COUNTER DRONE:'), ('test_player_swarm.gd', 'PLAYER SWARM:'), ('test_audio.gd', 'AUDIO:'), ('test_presentation_cache.gd', 'PRESENTATION CACHE:'), ('test_hitches.gd', 'HITCHES:'), ('test_large_terrain.gd', 'LARGE TERRAIN:')],
    # Harbor scenario probes the changelog cites as coverage (diagnostic-only probe_contact/probe_move excluded).
    'probes': [('probe_engage.gd', 'ENGAGE: PASS'), ('probe_crossing.gd', 'CROSSING: PASS'), ('probe_crowd.gd', 'CROWD: PASS'), ('probe_tank_crush_clear.gd', 'TANK CRUSH CLEAR: PASS'), ('probe_vehicle_path.gd', 'VEHICLE PATH:'), ('probe_resume.gd', 'RESUME: PASS'), ('probe_resume_harbor.gd', 'RESUME HARBOR: PASS'), ('probe_lethality.gd', 'LETHALITY: PASS')],
}
# New test_*.gd suites are discovered, so recent regressions cannot silently
# disappear from the default gate. Explicit markers below remain authoritative.
GROUPS["performance"] = [("test_cover_search_cost.gd", "COVER SEARCH COST:"),
                         ("profile_harbor_busy.gd", "HARBOR BUSY CPU:")]
registered = {script for entries in GROUPS.values() for script, _ in entries}
GROUPS["regression"] = [(path.name, None) for path in sorted((ROOT / "tests").glob("test_*.gd")) if path.name not in registered]
GROUPS["playthrough"] = [("harbor_playthrough.gd", "HARBOR PLAYTHROUGH:")]
RELEASE_SUITES = {
    "test_harbor_gameplay.gd", "test_field_victory.gd", "test_field_ops.gd",
    "test_field_ops_edges.gd", "test_field_ops_resume.gd", "test_engineer_works.gd",
    "test_input_actions.gd", "test_hud_states.gd", "test_notifications.gd",
    "test_hull_regroup.gd", "test_regroup_recovery.gd", "test_wreck_clearing.gd",
    "test_wreck_goal.gd", "test_atgm_flight.gd", "test_enemy_garrison.gd",
    "test_middle_pan.gd", "test_minimap_view.gd", "test_downed_section.gd",
    "test_garrison.gd", "test_garrison_fire.gd", "test_wave_strength.gd",
    "test_enemy_defences.gd", "test_cover_contact.gd", "test_release_info.gd", "test_release_flow.gd",
    "test_settings.gd", "test_tutorial.gd", "test_command_authority.gd",
    "test_command_modes.gd", "test_player_settings.gd",
    "test_battlefield_interface.gd", "test_enemy_knowledge.gd", "test_wave_overlap.gd",
    "test_cover_candidates.gd", "test_review_usability.gd", "test_harbor_diagnostics.gd",
    "test_wreck_section_recovery.gd",
    "test_riverside_navigation.gd", "test_scenario_dimensions.gd",
    "test_presentation_cache.gd", "test_regional_physics.gd", "test_regional_ui.gd",
}
GROUPS["release"] = [(script, marker) for group, entries in GROUPS.items()
                     if group not in ("performance", "playthrough")
                     for script, marker in entries if script in RELEASE_SUITES]
REGIONAL_SUITES = {
    "test_regional_physics.gd", "test_regional_ui.gd", "test_scenario_dimensions.gd",
    "test_road_network.gd", "test_field_ops.gd", "test_field_victory.gd",
    "test_harbor_gameplay.gd", "test_harbor_visuals.gd", "test_large_terrain.gd",
    "test_hud_layout.gd", "test_presentation_cache.gd",
}
GROUPS["regional"] = [(script, marker) for group, entries in GROUPS.items()
                      if group in ("core", "combat", "regression")
                      for script, marker in entries if script in REGIONAL_SUITES]
LONG = {"classic_playthrough.gd": 600, "test_city_urban.gd": 180,
        "harbor_playthrough.gd": 1800, "test_vehicle_jam.gd": 240,
        "test_harvester_dock.gd": 240, "test_harvester_threat.gd": 240,
        "test_wreck_clearing.gd": 240, "test_hitches.gd": 240,
        "test_cover_search_cost.gd": 180, "profile_harbor_busy.gd": 600}
DEFAULT_GROUPS = ("core", "combat", "probes", "regression")


def output_passed(code, output, marker):
    if code != 0 or re.search(r"SCRIPT ERROR|(?:^|\n)\s*FAIL(?:ED)?[: ]", output):
        return False
    if re.search(r"\b[1-9][0-9]* failures\b", output):
        return False
    if re.search(r"\b0 checks\b", output):
        return False
    if marker is not None:
        return marker in output
    # Discovered suites must report a completion summary as well as exiting 0.
    return bool(re.search(r"^[A-Z][A-Z0-9 _-]+:.*(?:\b0 failures\b|\bPASS\b)", output, re.M))


def find_engine():
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    mac = Path("/Applications/Godot.app/Contents/MacOS/Godot")
    return engine or (str(mac) if mac.is_file() else None)


def selected_suites(groups, names):
    seen = set()
    selected = []
    for group in groups:
        for script, marker in GROUPS[group]:
            if script not in seen and (not names or any(name in script for name in names)):
                selected.append((group, script, marker))
                seen.add(script)
    return selected


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", help="Only script names containing these substrings")
    parser.add_argument("--group", action="append", choices=tuple(GROUPS), help="May be repeated")
    parser.add_argument("--list", action="store_true", help="Print selected suites without running")
    parser.add_argument("--timeout", type=float, help="Override per-suite wall timeout in seconds")
    parser.add_argument("--verbose", action="store_true", help="Print passing suite logs too")
    args = parser.parse_args(argv)
    if args.timeout is not None and args.timeout <= 0:
        parser.error("--timeout must be positive")
    selected = selected_suites(args.group or DEFAULT_GROUPS, args.names)
    if not selected:
        parser.error("No checks matched")
    if args.list:
        for group, script, _ in selected:
            print(f"{group}/{script}")
        print(f"{len(selected)} suites; dedicated performance gates require --group performance")
        return 0
    engine = find_engine()
    if not engine:
        parser.error("Install Godot 4.5.1 or set GODOT_BIN")
    version = subprocess.check_output([engine, "--version"], text=True).strip()
    if not version.startswith("4.5.1."):
        parser.error(f"Expected Godot 4.5.1, found {version}")
    log_dir = Path(tempfile.mkdtemp(prefix="for-every-dawn-check-"))
    # Fresh checkouts need Godot's global class and resource import cache.
    # Isolate Linux user settings/reports without changing HOME or the host.
    environment = os.environ.copy()
    for key, directory in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        environment[key] = str(log_dir / directory)
        (log_dir / directory).mkdir()
    imported = subprocess.run([engine, "--headless", "--editor", "--path", str(ROOT),
                               "--log-file", str(log_dir / "import.log"), "--import"],
                              env=environment, text=True, capture_output=True, timeout=180)
    import_output = imported.stdout + imported.stderr
    (log_dir / "import.combined.log").write_text(import_output)
    if imported.returncode or "SCRIPT ERROR" in import_output:
        print(import_output, file=sys.stderr)
        print(f"Resource import failed; see {log_dir}", file=sys.stderr)
        return 1
    results = []
    for group, script, marker in selected:
        started = time.monotonic()
        timeout = args.timeout or LONG.get(script, 120)
        try:
            result = subprocess.run([engine, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                                     "--log-file", str(log_dir / f"{script}.log"), "--script", f"tests/{script}"],
                                    env=environment, text=True, capture_output=True, timeout=timeout)
            output, code = result.stdout + result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            output = "".join(part.decode(errors="replace") if isinstance(part, bytes) else (part or "")
                             for part in (error.stdout, error.stderr)) + f"\nTIMEOUT after {timeout}s"
            code = None
        seconds = round(time.monotonic() - started, 1)
        passed = output_passed(code, output, marker)
        (log_dir / f"{script}.combined.log").write_text(output)
        if args.verbose or not passed:
            print(output.strip())
        print(f"[check] {group}/{script}: {'PASS' if passed else 'FAIL'} in {seconds}s (exit {code})", flush=True)
        results.append({"group": group, "script": script, "passed": passed,
                        "exit_code": code, "seconds": seconds, "output": output.strip()})
    report = {"engine": version, "log_dir": str(log_dir), "groups": args.group or DEFAULT_GROUPS,
              "performance_acceptance": "Not established by functional runs; use isolated rendered benchmarks on supported hardware.",
              "results": results}
    report_text = json.dumps(report, indent=2) + "\n"
    (log_dir / "checks.json").write_text(report_text)
    (ROOT / "artifacts").mkdir(exist_ok=True)
    (ROOT / "artifacts" / "checks.json").write_text(report_text)
    failed = [r["script"] for r in results if not r["passed"]]
    print(f"[check] {len(results) - len(failed)}/{len(results)} passed in {sum(r['seconds'] for r in results):.0f}s; logs in {log_dir}")
    if failed:
        print("FAILED: " + ", ".join(failed), file=sys.stderr)
        return 1
    print("PASS: all selected checks.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
