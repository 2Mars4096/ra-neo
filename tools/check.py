#!/usr/bin/env python3
"""Run meaningful regressions; fail on script errors even when Godot exits zero.

Usage: tools/check.py [--group core|combat|probes ...] [name-substring ...]
With no arguments every group runs. Logs go to a fresh directory under the
system temp dir (honours $TMPDIR), so sandboxed runs never need /private/tmp.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
engine = os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
if not engine and Path('/Applications/Godot.app/Contents/MacOS/Godot').is_file():
    engine = '/Applications/Godot.app/Contents/MacOS/Godot'
if not engine:
    sys.exit('Install Godot 4.5.1 or set GODOT_BIN.')
GROUPS = {
    # Original regression set: maps, assets, navigation, UI, missions.
    'core': [('test_engineer_works.gd', 'ENGINEER WORKS:'), ('test_city_urban.gd', 'CITY URBAN:'), ('test_city_works.gd', 'CITY WORKS:'), ('test_assets_city.gd', 'ASSETS CITY:'), ('test_harbor_layout.gd', 'HARBOR LAYOUT TESTS:'), ('test_harbor_gameplay.gd', 'HARBOR GAMEPLAY:'), ('test_harbor_visuals.gd', 'HARBOR VISUALS:'), ('test_field_ops_resume.gd', 'FIELD OPS RESUME TESTS:'), ('test_field_geometry.gd', 'FIELD GEOMETRY:'), ('test_performance_repair.gd', 'PERFORMANCE REPAIR:'), ('test_field_ops.gd', 'FIELD OPS TESTS:'), ('test_field_ops_edges.gd', 'FIELD OPS EDGE TESTS:'), ('test_field_ui.gd', 'FIELD UI:'), ('test_field_visuals.gd', 'FIELD VISUALS:'), ('test_minimap_background.gd', 'MINIMAP BACKGROUND:'), ('test_asset_gallery.gd', 'ASSET GALLERY UI: 0 failures'), ('test_assets_street.gd', 'ASSETS STREET:'), ('test_assets_rural.gd', 'ASSETS RURAL:'), ('test_assets_waterfront.gd', 'WATERFRONT ASSETS:'), ('test_assets_battlefield.gd', 'BATTLEFIELD ASSETS:'), ('test_asset_library.gd', 'ASSET LIBRARY:'), ('test_asset_placement.gd', 'ASSET PLACEMENT:'), ('test_asset_palette.gd', 'ASSET PALETTE:'), ('test_review_usability.gd', 'REVIEW USABILITY:'), ('test_town_land_use.gd', 'TOWN LAND USE:'), ('test_classic_navigation.gd', 'CLASSIC NAVIGATION:'), ('test_environment_variants.gd', 'ENVIRONMENT VARIANTS:'), ('test_regroup_recovery.gd', 'REGROUP RECOVERY:'), ('test_riverside_navigation.gd', 'RIVERSIDE NAVIGATION:'), ('test_scenario_dimensions.gd', 'SCENARIO DIMENSIONS:'), ('test_town_design.gd', 'TOWN DESIGN:'), ('test_scene_air_clearance.gd', 'SCENE AIR CLEARANCE:'), ('test_tactical_flexibility.gd', 'TACTICAL FLEXIBILITY:'), ('test_architectural_parcels.gd', 'ARCHITECTURAL PARCELS:'), ('test_actor_spatial.gd', 'ACTOR SPATIAL:'), ('test_material_batching.gd', 'MATERIAL BATCHING: PASS'), ('test_roadside_props.gd', 'ROADSIDE PROPS:'), ('test_gap_navigation.gd', 'GAP NAVIGATION:'), ('test_mobility.gd', 'MOBILITY:'), ('test_road_network.gd', 'ROAD NETWORK:'), ('test_road_routing.gd', 'ROAD ROUTING:'), ('test_camera_zoom.gd', 'CAMERA ZOOM:'), ('test_hud_layout.gd', 'HUD LAYOUT:'), ('test_render_interpolation.gd', 'RENDER INTERPOLATION: PASS'), ('test_cover_behavior.gd', 'COVER BEHAVIOR:'), ('test_spatial_targeting.gd', 'SPATIAL TARGETING:'), ('test_classic_input.gd', 'CLASSIC INPUT:'), ('classic_playthrough.gd', 'CLASSIC MISSION:'), ('test_classic.gd', 'CLASSIC TESTS:'), ('test_stances.gd', 'STANCE TESTS:'), ('test_weather.gd', 'WEATHER TESTS:'), ('test_showcase.gd', 'SHOWCASE TESTS:'), ('test_showcase_motion.gd', 'SHOWCASE MOTION:'), ('showcase_playthrough.gd', 'SHOWCASE MISSION: PASS'), ('test_vehicle_stability.gd', 'STABILITY TESTS: PASS'), ('test_combat.gd', 'COMBAT TESTS:'), ('test_simulation.gd', 'SIMULATION TESTS:'), ('test_input.gd', 'INPUT TESTS:'), ('test_clearance.gd', 'CLEARANCE TESTS:'), ('test_effects.gd', 'EFFECTS TESTS:'), ('test_tactics.gd', 'TACTICS TESTS:'), ('test_animation.gd', 'ANIMATION TESTS:'), ('test_individuals.gd', 'INDIVIDUAL TESTS:'), ('playthrough.gd', 'PLAYTHROUGH VICTORY'), ('test_scenarios.gd', 'SCENARIO TESTS: PASS')],
    # Combat realism, damage, drones, re-crew and hitch suites (2026-10-14/15).
    'combat': [('test_garrison.gd', 'GARRISON:'), ('test_wounds.gd', 'WOUNDS:'), ('test_vehicle_damage.gd', 'VEHICLE DAMAGE:'), ('test_vehicle_followups.gd', 'VEHICLE FOLLOWUPS:'), ('test_world_damage.gd', 'WORLD DAMAGE:'), ('test_recrew.gd', 'RECREW:'), ('test_contact_drill.gd', 'CONTACT DRILL:'), ('test_soldier_targeting.gd', 'SOLDIER TARGETING:'), ('test_per_body_cover.gd', 'PER-BODY COVER:'), ('test_wave_strength.gd', 'WAVE STRENGTH:'), ('test_enemy_defences.gd', 'ENEMY DEFENCES:'), ('test_counter_drone.gd', 'COUNTER DRONE:'), ('test_player_swarm.gd', 'PLAYER SWARM:'), ('test_audio.gd', 'AUDIO:'), ('test_presentation_cache.gd', 'PRESENTATION CACHE:'), ('test_hitches.gd', 'HITCHES:'), ('test_large_terrain.gd', 'LARGE TERRAIN:')],
    # Harbor scenario probes the changelog cites as coverage (diagnostic-only probe_contact/probe_move excluded).
    'probes': [('probe_engage.gd', 'ENGAGE: PASS'), ('probe_crossing.gd', 'CROSSING: PASS'), ('probe_crowd.gd', 'CROWD: PASS'), ('probe_tank_crush_clear.gd', 'TANK CRUSH CLEAR: PASS'), ('probe_vehicle_path.gd', 'VEHICLE PATH:'), ('probe_resume.gd', 'RESUME: PASS'), ('probe_resume_harbor.gd', 'RESUME HARBOR: PASS'), ('probe_lethality.gd', 'LETHALITY: PASS')],
}
# Seconds; everything else gets DEFAULT_TIMEOUT.
LONG = {'classic_playthrough.gd': 180, 'test_city_urban.gd': 180}
DEFAULT_TIMEOUT = 90
args = sys.argv[1:]
groups = [args[i + 1] for i, a in enumerate(args) if a == '--group' and i + 1 < len(args)]
names = [a for i, a in enumerate(args) if a != '--group' and (i == 0 or args[i - 1] != '--group')]
unknown = [g for g in groups if g not in GROUPS]
if unknown:
    sys.exit(f'Unknown group(s) {unknown}; choose from {list(GROUPS)}.')
selected = [(g, s, m) for g in (groups or GROUPS) for s, m in GROUPS[g] if not names or any(n in s for n in names)]
log_dir = Path(tempfile.mkdtemp(prefix='ra-neo-check-'))
results = []
for group, script, marker in selected:
    started = time.monotonic()
    try:
        result = subprocess.run([engine, '--headless', '--path', str(ROOT), '--log-file', str(log_dir / f'{script}.log'), '--script', f'tests/{script}'], text=True, capture_output=True, timeout=LONG.get(script, DEFAULT_TIMEOUT))
        output, code = result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        # A GDScript error leaves --script runs hanging; report it instead of aborting the batch.
        output = ''.join(part.decode(errors='replace') if isinstance(part, bytes) else (part or '') for part in (error.stdout, error.stderr)) + f'\nTIMEOUT after {error.timeout}s'
        code = None
    seconds = round(time.monotonic() - started, 1)
    # macOS sandbox certificate discovery emits an unrelated engine diagnostic.
    passed = code == 0 and marker in output and 'SCRIPT ERROR' not in output and 'FAIL:' not in output
    print(output.strip())
    print(f'[check] {group}/{script}: {"PASS" if passed else "FAIL"} in {seconds}s (exit {code})')
    results.append({'group': group, 'script': script, 'passed': passed, 'exit_code': code, 'seconds': seconds, 'output': output.strip()})
report = {'engine': subprocess.check_output([engine, '--version'], text=True).strip(), 'log_dir': str(log_dir), 'results': results}
(ROOT / 'artifacts' / 'checks.json').write_text(json.dumps(report, indent=2) + '\n')
failed = [r['script'] for r in results if not r['passed']]
print(f'[check] {len(results) - len(failed)}/{len(results)} passed in {sum(r["seconds"] for r in results):.0f}s; logs in {log_dir}')
if failed or not results:
    sys.exit('FAILED: ' + ', '.join(failed) if failed else 'No checks matched.')
print('PASS: simulation, viewport input, restart, and end-to-end mission checks.')
