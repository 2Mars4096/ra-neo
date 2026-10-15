#!/usr/bin/env python3
"""Add tier-1 engineer field works to resources/field_units.json (idempotent).

Costs/times are game-balance choices (docs/harbor-city-design.md), not real estimates.
`zone` describes non-solid effects applied by FieldOps/terrain once complete:
speed multipliers per mobility profile, cover classes, concealment and crushing.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "resources/field_units.json"
WORKS = {
    "concertina_wire": dict(name="CONCERTINA WIRE", hp=80, cost=40, build_seconds=6, footprint=[7.0, 1.4], solid=False,
                            zone={"speed": {"infantry": 0.15}, "crushable": True}),
    "tank_obstacles": dict(name="ANTI-TANK OBSTACLES", hp=420, cost=70, build_seconds=10, footprint=[6.4, 2.4], solid=False,
                           zone={"speed": {"tracked": 0.03, "wheeled": 0.03, "infantry": 0.85}, "cover": ["infantry"]}),
    "fighting_trench": dict(name="FIGHTING TRENCH", hp=320, cost=50, build_seconds=10, footprint=[7.0, 2.0], solid=False,
                            zone={"speed": {"infantry": 0.8, "tracked": 0.5, "wheeled": 0.3}, "cover": ["infantry"]}),
    "vehicle_berm": dict(name="VEHICLE BERM", hp=360, cost=60, build_seconds=12, footprint=[6.0, 6.0], solid=False,
                         zone={"cover": ["vehicle"]}),
    "camouflage_net": dict(name="CAMOUFLAGE NET", hp=90, cost=40, build_seconds=6, footprint=[5.6, 4.8], solid=False,
                           zone={"conceal": 0.5}),
    "forward_supply_point": dict(name="FORWARD SUPPLY POINT", hp=260, cost=150, build_seconds=18, footprint=[6.0, 5.0], solid=True,
                                 zone={}),
}

# Armed and command emplacements. `armed` structures fire with their combat_alias
# weapon row once complete (bunker = machine gun, gun pit = anti-tank).
# Enemy prepared positions use the same definitions, spawned already complete.
EMPLACEMENTS = {
    "bunker": dict(name="MG BUNKER", hp=900, cost=180, build_seconds=22, footprint=[4.4, 3.6], armor=1,
                   range=17, sight=20, damage=11, interval=0.32, armed=True, alias="rifle"),
    "at_gun": dict(name="AT GUN PIT", hp=260, cost=160, build_seconds=16, footprint=[4.2, 4.2], armor=0,
                   range=24, sight=21, damage=52, interval=3.6, armed=True, alias="atgm"),
    "command_post": dict(name="COMMAND POST", hp=520, cost=130, build_seconds=16, footprint=[5.0, 4.2], armor=0,
                         range=0, sight=28, damage=0, interval=0.9, armed=False, alias="rifle"),
    "ammo_depot": dict(name="AMMO DEPOT", hp=420, cost=120, build_seconds=14, footprint=[6.0, 4.4], armor=0,
                       range=0, sight=0, damage=0, interval=0.9, armed=False, alias="rifle"),
}

def main():
    data = json.loads(PATH.read_text())
    for kind, spec in WORKS.items():
        w, d = spec["footprint"]
        data[kind] = {"name": spec["name"], "role": "Engineer-built field support", "domain": "land", "hp": spec["hp"],
                      "speed": 0, "range": 0, "sight": 0, "damage": 0, "interval": 0.9, "armor": 0, "cost": spec["cost"],
                      "air": False, "members": 0, "radius": math.hypot(w, d) / 2 * 0.5 if not spec["solid"] else math.hypot(w, d) / 2,
                      "altitude": 0.0, "structure": True, "footprint": spec["footprint"], "build_seconds": spec["build_seconds"],
                      "solid": spec["solid"], "zone": spec["zone"], "combat_alias": "rifle", "render_alias": kind}
    for kind, spec in EMPLACEMENTS.items():
        w, d = spec["footprint"]
        data[kind] = {"name": spec["name"], "role": "Engineer-built emplacement", "domain": "land", "hp": spec["hp"],
                      "speed": 0, "range": spec["range"], "sight": spec["sight"], "damage": spec["damage"],
                      "interval": spec["interval"], "armor": spec["armor"], "cost": spec["cost"], "air": spec["alias"] == "rifle",
                      "members": 0, "radius": math.hypot(w, d) / 2, "altitude": 0.0, "structure": True,
                      "footprint": spec["footprint"], "build_seconds": spec["build_seconds"], "solid": True, "zone": {},
                      "armed": spec["armed"], "combat_alias": spec["alias"], "render_alias": kind}
    PATH.write_text(json.dumps(data, indent=2) + "\n")
    print(f"{len(WORKS)+len(EMPLACEMENTS)} engineer works; {len(data)} field definitions")

if __name__ == "__main__":
    main()
