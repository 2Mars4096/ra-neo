#!/usr/bin/env python3
"""Run meaningful regressions; fail on script errors even when Godot exits zero."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
engine = os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
if not engine and Path('/Applications/Godot.app/Contents/MacOS/Godot').is_file():
    engine = '/Applications/Godot.app/Contents/MacOS/Godot'
if not engine:
    sys.exit('Install Godot 4.5.1 or set GODOT_BIN.')
results = []
for script, marker in [('test_engineer_works.gd', 'ENGINEER WORKS:'), ('test_city_urban.gd', 'CITY URBAN:'), ('test_city_works.gd', 'CITY WORKS:'), ('test_assets_city.gd', 'ASSETS CITY:'), ('test_harbor_layout.gd', 'HARBOR LAYOUT TESTS:'), ('test_harbor_gameplay.gd', 'HARBOR GAMEPLAY:'), ('test_harbor_visuals.gd', 'HARBOR VISUALS:'), ('test_field_ops_resume.gd', 'FIELD OPS RESUME TESTS:'), ('test_field_geometry.gd', 'FIELD GEOMETRY:'), ('test_performance_repair.gd', 'PERFORMANCE REPAIR:'), ('test_field_ops.gd', 'FIELD OPS TESTS:'), ('test_field_ops_edges.gd', 'FIELD OPS EDGE TESTS:'), ('test_field_ui.gd', 'FIELD UI:'), ('test_field_visuals.gd', 'FIELD VISUALS:'), ('test_minimap_background.gd', 'MINIMAP BACKGROUND:'), ('test_asset_gallery.gd', 'ASSET GALLERY UI: 0 failures'), ('test_assets_street.gd', 'ASSETS STREET:'), ('test_assets_rural.gd', 'ASSETS RURAL:'), ('test_assets_waterfront.gd', 'WATERFRONT ASSETS:'), ('test_assets_battlefield.gd', 'BATTLEFIELD ASSETS:'), ('test_asset_library.gd', 'ASSET LIBRARY:'), ('test_asset_placement.gd', 'ASSET PLACEMENT:'), ('test_asset_palette.gd', 'ASSET PALETTE:'), ('test_review_usability.gd', 'REVIEW USABILITY:'), ('test_town_land_use.gd', 'TOWN LAND USE:'), ('test_classic_navigation.gd', 'CLASSIC NAVIGATION:'), ('test_environment_variants.gd', 'ENVIRONMENT VARIANTS:'), ('test_regroup_recovery.gd', 'REGROUP RECOVERY:'), ('test_riverside_navigation.gd', 'RIVERSIDE NAVIGATION:'), ('test_scenario_dimensions.gd', 'SCENARIO DIMENSIONS:'), ('test_town_design.gd', 'TOWN DESIGN:'), ('test_scene_air_clearance.gd', 'SCENE AIR CLEARANCE:'), ('test_tactical_flexibility.gd', 'TACTICAL FLEXIBILITY:'), ('test_architectural_parcels.gd', 'ARCHITECTURAL PARCELS:'), ('test_actor_spatial.gd', 'ACTOR SPATIAL:'), ('test_material_batching.gd', 'MATERIAL BATCHING: PASS'), ('test_roadside_props.gd', 'ROADSIDE PROPS:'), ('test_gap_navigation.gd', 'GAP NAVIGATION:'), ('test_mobility.gd', 'MOBILITY:'), ('test_road_network.gd', 'ROAD NETWORK:'), ('test_road_routing.gd', 'ROAD ROUTING:'), ('test_camera_zoom.gd', 'CAMERA ZOOM:'), ('test_hud_layout.gd', 'HUD LAYOUT:'), ('test_render_interpolation.gd', 'RENDER INTERPOLATION: PASS'), ('test_cover_behavior.gd', 'COVER BEHAVIOR:'), ('test_spatial_targeting.gd', 'SPATIAL TARGETING:'), ('test_classic_input.gd', 'CLASSIC INPUT:'), ('classic_playthrough.gd', 'CLASSIC MISSION:'), ('test_classic.gd', 'CLASSIC TESTS:'), ('test_stances.gd', 'STANCE TESTS:'), ('test_weather.gd', 'WEATHER TESTS:'), ('test_showcase.gd', 'SHOWCASE TESTS:'), ('test_showcase_motion.gd', 'SHOWCASE MOTION:'), ('showcase_playthrough.gd', 'SHOWCASE MISSION: PASS'), ('test_vehicle_stability.gd', 'STABILITY TESTS: PASS'), ('test_combat.gd', 'COMBAT TESTS:'), ('test_simulation.gd', 'SIMULATION TESTS:'), ('test_input.gd', 'INPUT TESTS:'), ('test_clearance.gd', 'CLEARANCE TESTS:'), ('test_effects.gd', 'EFFECTS TESTS:'), ('test_tactics.gd', 'TACTICS TESTS:'), ('test_animation.gd', 'ANIMATION TESTS:'), ('test_individuals.gd', 'INDIVIDUAL TESTS:'), ('playthrough.gd', 'PLAYTHROUGH VICTORY'), ('test_scenarios.gd', 'SCENARIO TESTS: PASS')]:
    result = subprocess.run([engine, '--headless', '--path', str(ROOT), '--log-file', '/private/tmp/ra-neo-check.log' if sys.platform=='darwin' else '/tmp/ra-neo-check.log', '--script', f'tests/{script}'], text=True, capture_output=True, timeout=180 if script=='classic_playthrough.gd' else 90)
    output = result.stdout + result.stderr
    # macOS sandbox certificate discovery emits an unrelated engine diagnostic.
    passed = result.returncode == 0 and marker in output and 'SCRIPT ERROR' not in output and 'FAIL:' not in output
    print(output.strip())
    results.append({'script': script, 'passed': passed, 'output': output.strip()})
report = {'engine': subprocess.check_output([engine, '--version'],text=True).strip(), 'results': results}
(ROOT/'artifacts'/'checks.json').write_text(json.dumps(report,indent=2)+'\n')
if not all(r['passed'] for r in results):
    sys.exit(1)
print('PASS: simulation, viewport input, restart, and end-to-end mission checks.')
