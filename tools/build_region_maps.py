#!/usr/bin/env python3
"""Compile regional blueprints through the existing Harbor geometry pipeline.

Run ``python3 tools/build_region_maps.py [--check]``. Each output is a separate
lazy-loaded map; resources/scenarios.json and its historical indices stay fixed.
"""
from __future__ import annotations

import argparse
from collections import Counter, deque
import copy
import json
import math
from pathlib import Path

import build_harbor_map as harbor
from regional_map_schema import validate_blueprint

ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT_DIR = ROOT / "resources/maps/blueprints"
OUTPUT_DIR = ROOT / "resources/maps/region"


def encode_json(value) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"


serialize_config = encode_json


def _prop_key(item):
    return (item["id"], tuple(round(v, 4) for v in item["position"]), round(item.get("rotation_degrees", 0) % 360, 4))


def _prepare(data):
    bp = copy.deepcopy(data)
    for key in ["streets", "city_districts", "rock_parcels", "landmarks", "decor", "open_spaces", "footpaths", "crane_rails", "port_fence", "compound_fence", "quay_walls", "damage_front"]:
        bp.setdefault(key, [])
    bp.setdefault("layout_validation", {})
    bp.setdefault("proposal", {"status": "authored regional battlefield", "inspiration": "Compressed fictional Black Sea geography."})
    bp["source_path"] = f"resources/maps/blueprints/{bp['scenario']['id']}.json"
    bp["generate_enemy_defences"] = False
    bp["explicit_decor_first"] = True
    sc = bp["scenario"]
    sc.update(mode="field_ops", style="showcase", port=False, map_renderer="harbor", hidden=False)
    sc.setdefault("nav_cell_size", 4)
    sc.setdefault("fog_cell_size", 4)
    sc.setdefault("shore_x", sc["size"][0])
    sc.setdefault("woods", [])
    sc.setdefault("rubble", [0, 0, 0, 0])
    sc.setdefault("mud", [0, 0, 0, 0])
    sc.setdefault("water_polygons", [])
    sc.setdefault("resource_fields", [])
    sc.setdefault("field_supply", 3200)
    sc.setdefault("field_income", 6)
    sc.setdefault("hold", 60)
    sc.setdefault("autonomy", True)
    sc.setdefault("air_altitudes", {"drone": 11, "helo": 13})
    sc.setdefault("available_domains", ["land", "air", "sea"] if sc["water_polygons"] else ["land", "air"])
    sc.setdefault("enemy_works", [])
    sc.setdefault("reserve_force", [])
    sc.setdefault("enemy_waves", {"first": 90, "interval": 95, "max_wave": 6})

    # Tracks are existing low, traversable registry meshes. Their ballast strip
    # reserves room against generated buildings, and parked wagons remain real
    # solid registry props. This does not implement moving trains or tunnels.
    for line in bp.get("railways", []):
        for i, (a, b) in enumerate(zip(line["points"], line["points"][1:])):
            delta = harbor.sub(b, a)
            length = harbor.length(delta)
            direction = harbor.unit(delta)
            yaw = harbor.yaw_of(direction)
            middle = harbor.mul(harbor.add(a, b), .5)
            poly = harbor.obb(middle, length, 7, yaw)
            bp["open_spaces"].append({"name": f"{line['name']} ballast {i+1}", "kind": "railway", "polygon": [list(v) for v in poly]})
            centers = [12+24*k for k in range(max(1, math.floor(length/24)))]
            if centers[-1]+12 < length-.001:
                centers.append(length-12)
            for t in centers:
                p = harbor.add(a, harbor.mul(direction, t))
                bp["decor"].append({"id": "rail_siding.straight", "position": list(p), "rotation_degrees": yaw,
                                    "context": f"{line['name']}; static traversable rail", "allow_reserved": True})

    # An explicit solid object reserves its plot before procedural buildings are
    # grown. Its exact footprint still comes from the asset registry at emission.
    library = harbor.load_library()
    for i, item in enumerate(bp["decor"]):
        if library[item["id"]]["collision"] == "flat":
            continue
        r = harbor.aabb(library[item["id"]]["footprint"], item["position"], item.get("rotation_degrees", 0))
        bp["open_spaces"].append({"name": f"Authored asset {i+1}", "kind": "authored_asset", "polygon": [list(v) for v in harbor.rect_poly([r[0]-.4, r[1]-.4, r[2]+.8, r[3]+.8])]})
    return bp


def compile_blueprint(data: dict) -> dict:
    """Pure deterministic compile. Invalid authored geometry raises ValueError."""
    issues = validate_blueprint(data)
    if issues:
        raise ValueError("\n".join(issues))
    bp = _prepare(data)
    result = harbor.compile_map(bp, draft=True)
    actual = Counter(_prop_key(p) for p in result["map_props"])
    for p in bp["decor"]:
        key = _prop_key(p)
        if not actual[key]:
            raise ValueError(f"Cannot place {p['id']} at {p['position']}: check land/sea, road, rock, building, spawn and object clearance.")
        actual[key] -= 1
    result["railways"] = copy.deepcopy(data.get("railways", []))
    result["authoring_stats"] = {
        "buildings": result["building_count"], "props": len(result["map_props"]),
        "road_segments": len(result["roads"]["edges"]), "rock_parcels": len(bp["rock_parcels"]),
        "rail_segments": sum(len(r["points"])-1 for r in data.get("railways", [])),
    }
    issues = validate_compiled(result)
    if issues:
        raise ValueError("\n".join(issues))
    return result


class MapClearance:
    """Conservative authoring-time footprint checks, plus coarse route evidence.

    Native Godot tests remain authoritative. These checks prevent editor saves
    with obvious unsupported surfaces or disconnected capture/insertion sites.
    Route checks cover footprint and water connectivity. Profile-specific slope
    access is checked natively; an infantry lookout need not be reachable by armor.
    """
    def __init__(self, sc):
        self.sc = sc
        self.width, self.height = sc["size"]
        self.water = sc.get("water_polygons", [])
        self.coast = [edge for poly in self.water for edge in harbor.edges(poly)]
        self.index = harbor.Grid(16)
        for domain, rects in [("land", sc.get("blocks", [])+sc.get("prop_blocks", [])), ("sea", sc.get("water_blocks", []))]:
            for rect in rects:
                self.index.insert(harbor.bbox(harbor.rect_poly(rect)), (domain, rect))
        # Terrain's authored woods also contain physical trees on both margins.
        for x, z, w, h in sc.get("woods", []):
            for side in [1, w-1]:
                for dz in range(1, int(h), 4):
                    p = (x+side, z+dz)
                    self.index.insert((p[0]-1.2, p[1]-1.2, p[0]+1.2, p[1]+1.2), ("land", [p[0]-1.2,p[1]-1.2,2.4,2.4]))

    def is_water(self, p):
        return any(harbor.in_poly(p, poly) for poly in self.water) if self.water else p[0] >= self.sc.get("shore_x", self.width)

    def clear(self, p, radius=2.77, domain="land"):
        x, z = p
        if x < radius or z < radius or x > self.width-radius or z > self.height-radius:
            return False
        if domain == "air":
            return True
        if self.is_water(p) != (domain == "sea"):
            return False
        if any(harbor.seg_dist(p, a, b) < radius for a, b in self.coast):
            return False
        for kind, r in self.index.query((x-radius,z-radius,x+radius,z+radius)):
            if kind != domain:
                continue
            dx = max(r[0]-x, 0, x-(r[0]+r[2]))
            dz = max(r[1]-z, 0, z-(r[1]+r[3]))
            if dx*dx+dz*dz < radius*radius:
                return False
        return True

    def segment_clear(self, a, b, radius=2.77, domain="land"):
        count = max(1, math.ceil(harbor.length(harbor.sub(b,a))))
        return all(self.clear(harbor.add(a, harbor.mul(harbor.sub(b,a), k/count)), radius, domain) for k in range(count+1))

    def connected(self, start, targets, radius=2.77, domain="land", cell=4):
        """Return the target indices unreachable by a supported footprint."""
        if not targets:
            return []
        nx, nz = math.ceil(self.width/cell), math.ceil(self.height/cell)
        def pos(key): return (key[0]*cell+cell/2, key[1]*cell+cell/2)
        cache = {}
        def allowed(k):
            if k not in cache:
                cache[k] = 0 <= k[0] < nx and 0 <= k[1] < nz and self.clear(pos(k), radius, domain)
            return cache[k]
        def anchors(p):
            center = (int(p[0]/cell),int(p[1]/cell))
            return {(center[0]+dx, center[1]+dz) for dx in range(-2,3) for dz in range(-2,3)
                    if allowed((center[0]+dx,center[1]+dz)) and self.segment_clear(p,pos((center[0]+dx,center[1]+dz)),radius,domain)}
        starts = anchors(start)
        target_sets = [anchors(p) for p in targets]
        pending = set(range(len(targets)))
        seen = set(starts)
        q = deque(starts)
        while q and pending:
            current = q.popleft()
            pending = {i for i in pending if current not in target_sets[i]}
            for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
                nxt=(current[0]+dx,current[1]+dz)
                if nxt not in seen and allowed(nxt) and self.segment_clear(pos(current),pos(nxt),radius,domain):
                    seen.add(nxt);q.append(nxt)
        return sorted(pending)


def validate_compiled(sc: dict) -> list[str]:
    errors=[]
    clearance=MapClearance(sc)
    # Buildings are rigid parcels, so a plateau can support them but a steep
    # ramp cannot be hidden beneath their floor. Match Elevation.height_at's
    # max-combined smooth ramps while keeping this authoring check independent
    # of runtime navigation and its deliberately different mobility profiles.
    if sc.get("elevation"):
        def ground_height(point):
            result = 0.0
            for patch in sc["elevation"]:
                x, y, w, h = patch["rect"]
                dx = max(x-point[0], 0, point[0]-x-w)
                dy = max(y-point[1], 0, point[1]-y-h)
                t = max(0.0, 1.0-math.hypot(dx,dy)/patch["ramp"])
                result = max(result, t*t*(3-2*t)*patch["height"])
            return result
        for building in sc.get("architecture", []):
            if building.get("design") == "rock" or not building.get("source_size"):
                continue
            w, h = building["source_size"]
            points = harbor.obb(building["position"],w,h,building.get("rotation_degrees",0))
            heights = [ground_height(p) for p in points]+[ground_height(building["position"])]
            if max(heights)-min(heights) > .5:
                errors.append(f"Building {building.get('design','')} at {building['position']} crosses an elevation ramp; move it onto a flat terrace.")
    units=json.loads((ROOT/"resources/units.json").read_text())
    units.update(json.loads((ROOT/"resources/field_units.json").read_text()))
    for side in ["player_force","enemy_force","reserve_force"]:
        for i,u in enumerate(sc.get(side,[])):
            definition=units[u["kind"]]
            domain=definition.get("domain","land")
            if domain not in sc.get("available_domains",["land","air","sea"]):
                errors.append(f"{side} {i+1}: {domain} units are disabled on this battlefield.")
            if not clearance.clear(u["position"],float(definition.get("radius",2.65))+.12,domain):
                errors.append(f"{side} {i+1} ({u['kind']}) at {u['position']} lacks physical {domain} clearance.")
    goals = list(sc["objectives"])+[sc["field_enemy_insertion"]]
    for i,p in enumerate([sc["field_insertion"]]+goals):
        if not clearance.clear(p):
            errors.append(f"{'Player insertion' if i==0 else 'Objective/enemy insertion '+str(i)} at {p} lacks land clearance.")
    for i, facility in enumerate(sc.get("operation", {}).get("facilities", [])):
        if "forward_position" not in facility:
            continue
        p = facility["forward_position"]
        if not clearance.clear(p):
            errors.append(f"Facility {i+1} forward insertion at {p} lacks land clearance.")
        else:
            goals.append(p)
    if not errors:
        for index in clearance.connected(sc["field_insertion"],goals):
            errors.append(f"Objective/enemy insertion {index+1} has no conservative land route from player insertion.")
    if "sea" in sc.get("available_domains",[]):
        sea=sc.get("field_sea_insertion")
        if not sea or not clearance.clear(sea,float(units["boat"]["radius"])+.12,"sea"):
            errors.append("Sea reinforcements require an unobstructed sea insertion.")
        elif not errors:
            boats=[u["position"] for k in ["player_force","enemy_force"] for u in sc.get(k,[]) if u["kind"]=="boat"]
            zone = sc.get("operation", {}).get("naval_zone")
            if zone:
                if not clearance.clear(zone["position"],float(units["boat"]["radius"])+.12,"sea"):
                    errors.append("Naval control zone needs an unobstructed water position for a boat.")
                boats.append(zone["position"])
            if clearance.connected(sea,boats,float(units["boat"]["radius"])+.12,"sea"):
                errors.append("A boat or naval control zone is disconnected from the sea insertion.")
    fields=json.loads((ROOT/"resources/field_units.json").read_text())
    for i,w in enumerate(sc.get("enemy_works",[])):
        spec=fields.get(w.get("kind"),{})
        if not spec or "footprint" not in spec:
            errors.append(f"Enemy work {i+1}: unknown structure.");continue
        width,depth=spec["footprint"]
        if w.get("rotated",False):width,depth=depth,width
        p=w["position"]
        for dx,dz in [(0,0),(-width/2,-depth/2),(width/2,-depth/2),(width/2,depth/2),(-width/2,depth/2)]:
            if not clearance.clear([p[0]+dx,p[1]+dz],.15):
                errors.append(f"Enemy work {i+1} at {p} overlaps terrain or scenery.");break
    return errors


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--map",help="Compile one stable battlefield id")
    args=parser.parse_args()
    paths=sorted(BLUEPRINT_DIR.glob("*.json"))
    if args.map:paths=[p for p in paths if p.stem==args.map]
    if not paths:raise SystemExit("No matching regional blueprints.")
    outputs=[]
    for path in paths:
        data=json.loads(path.read_text())
        if data["scenario"]["id"]!=path.stem:raise SystemExit(f"{path.name}: id must match filename.")
        try:sc=compile_blueprint(data)
        except (ValueError,KeyError,TypeError) as exc:raise SystemExit(f"{path.name}: {exc}") from exc
        outputs.append((OUTPUT_DIR/path.name,encode_json(sc)))
        print(f"{sc['id']}: {sc['authoring_stats']}")
    # Compile and validate every requested map before touching any output.
    for destination,text in outputs:
        if args.check:
            if not destination.exists() or destination.read_text()!=text:raise SystemExit(f"{destination.name}: generated map is stale; run tools/build_region_maps.py")
        else:
            destination.parent.mkdir(parents=True,exist_ok=True)
            destination.write_text(text)
    print("REGIONAL COMPILER: reproducible" if args.check else "REGIONAL COMPILER: written")


if __name__=="__main__":main()
