#!/usr/bin/env python3
"""Shared validation for the regional authoring tools (no third-party packages).

Blueprints deliberately extend the Harbor authoring format. They never author a
second collision system: the existing compiler emits the runtime rectangles.
"""
from __future__ import annotations

import math
import re
from pathlib import Path
import build_harbor_map as harbor

ROOT = Path(__file__).resolve().parents[1]
MORPHOLOGIES = {"perimeter", "private", "superblock", "port", "village", "north", "garages", "natural"}


def _number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _vector(value, size):
    return isinstance(value, list) and len(value) == size and all(_number(v) for v in value)


def validate_blueprint(data: dict) -> list[str]:
    """Return actionable authoring errors, without changing the input."""
    errors = []
    if not isinstance(data, dict):
        return ["Blueprint must be a JSON object."]
    sc = data.get("scenario")
    if not isinstance(sc, dict):
        return ["scenario must be an object."]
    if not re.fullmatch(r"[a-z][a-z0-9_]{1,63}", str(sc.get("id", ""))):
        errors.append("scenario.id must be a stable lowercase identifier.")
    if not isinstance(sc.get("name"), str) or not sc["name"].strip():
        errors.append("scenario.name is required.")
    size = sc.get("size")
    if not _vector(size, 2) or any(v < 64 or v > 2048 for v in size):
        return errors + ["scenario.size must contain finite dimensions between 64 and 2048."]
    width, height = size

    def point(p, label):
        if not _vector(p, 2):
            errors.append(f"{label}: expected a finite [x, y] point.")
            return False
        if not 0 <= p[0] <= width or not 0 <= p[1] <= height:
            errors.append(f"{label}: point lies outside the battlefield.")
            return False
        return True

    def rect(r, label):
        if not _vector(r, 4) or min(r[2:]) <= 0:
            errors.append(f"{label}: expected [x, y, positive width, positive height].")
            return False
        return point(r[:2], label) and point([r[0]+r[2], r[1]+r[3]], label)

    def polygon(p, label):
        if not isinstance(p, list) or len(p) < 3:
            errors.append(f"{label}: a polygon needs at least three points.")
            return False
        if not all(point(v, label) for v in p):
            return False
        if abs(harbor.area(p)) < .01:
            errors.append(f"{label}: polygon has no area.")
            return False
        segments = list(harbor.edges(p))
        for i, (a, b) in enumerate(segments):
            if harbor.length(harbor.sub(b, a)) < .001:
                errors.append(f"{label}: polygon contains a zero-length edge.")
            for j, (c, d) in enumerate(segments):
                if j <= i+1 or (i == 0 and j == len(segments)-1):
                    continue
                if harbor.seg_hit(a, b, c, d):
                    errors.append(f"{label}: polygon crosses itself.")
                    return False
        return True

    required_arrays = ["streets", "city_districts", "rock_parcels", "landmarks", "decor", "open_spaces"]
    for key in required_arrays:
        if not isinstance(data.get(key, []), list):
            errors.append(f"{key} must be an array.")
    for key in ["water_polygons", "woods", "objectives", "sectors", "player_force", "enemy_force"]:
        if not isinstance(sc.get(key, []), list):
            errors.append(f"scenario.{key} must be an array.")
    if errors:
        return errors
    water = sc.get("water_polygons", [])
    for i, p in enumerate(water):
        polygon(p, f"Water polygon {i+1}")
    rocks = data.get("rock_parcels", [])
    for i, r in enumerate(rocks):
        rect(r, f"Rock parcel {i+1}")
    for i, r in enumerate(sc.get("woods", [])):
        rect(r, f"Woods {i+1}")
    for key in ["rubble", "mud"]:
        if key in sc:
            r = sc[key]
            if not _vector(r, 4) or min(r[2:]) < 0:
                errors.append(f"scenario.{key}: expected a rectangle; zero size disables the patch.")
            elif max(r[2:]) > 0:
                rect(r, f"scenario.{key}")
    districts = set()
    for i, d in enumerate(data.get("city_districts", [])):
        if not isinstance(d, dict):
            errors.append(f"District {i+1} must be an object.")
            continue
        ident = d.get("id", "")
        if not isinstance(ident, str) or not ident or ident in districts:
            errors.append(f"District {i+1} needs a unique id.")
        districts.add(str(ident))
        if d.get("morphology") not in MORPHOLOGIES:
            errors.append(f"District {ident}: unknown morphology.")
        polygon(d.get("polygon"), f"District {ident}")
    for i, o in enumerate(data.get("open_spaces", [])):
        if not isinstance(o, dict):
            errors.append(f"Open space {i+1} must be an object.")
            continue
        if not isinstance(o.get("name"), str) or not isinstance(o.get("kind"), str):
            errors.append(f"Open space {i+1} needs name and kind.")
        polygon(o.get("polygon"), f"Open space {i+1}")

    lines = []
    for kind in ["streets", "railways"]:
        items = data.get(kind, [])
        if not isinstance(items, list):
            errors.append(f"{kind} must be an array.")
            continue
        names = set()
        for i, st in enumerate(items):
            label = f"{kind} {i+1}"
            if not isinstance(st, dict):
                errors.append(f"{label} must be an object.")
                continue
            name = st.get("name", "")
            if not isinstance(name, str) or not name.strip() or name in names:
                errors.append(f"{label} needs a unique name.")
            names.add(str(name))
            points = st.get("points")
            if not isinstance(points, list) or len(points) < 2:
                errors.append(f"{label} needs at least two points.")
                continue
            if not all(point(p, name) for p in points):
                continue
            w = st.get("width", 3 if kind == "railways" else 0)
            if not _number(w) or w < (3 if kind == "railways" else 4) or w > 32:
                errors.append(f"{name}: invalid corridor width.")
                continue
            for a, b in zip(points, points[1:]):
                length = harbor.length(harbor.sub(b, a))
                if length < (24 if kind == "railways" else 1):
                    errors.append(f"{name}: segments must be at least {'24' if kind == 'railways' else '1'} units long.")
                lines.append((str(name), a, b, w))

    designs = harbor.load_designs()
    library = harbor.load_library()
    for i, lm in enumerate(data.get("landmarks", [])):
        if not isinstance(lm, dict):
            errors.append(f"Landmark {i+1} must be an object.")
            continue
        point(lm.get("position"), f"Landmark {i+1}")
        if lm.get("design") not in designs:
            errors.append(f"Landmark {i+1}: unknown building design.")
        dims = lm.get("source_size")
        if not _vector(dims, 2) or any(v <= 0 or v > 100 for v in dims):
            errors.append(f"Landmark {i+1}: invalid building dimensions.")
        elif lm.get("design") in designs:
            family = designs[lm["design"]]
            if not family["w"][0] <= dims[0] <= family["w"][1] or not family["d"][0] <= dims[1] <= family["d"][1]:
                errors.append(f"Landmark {i+1}: dimensions must stay within the {lm['design']} family bounds.")
        if not _number(lm.get("rotation_degrees", 0)):
            errors.append(f"Landmark {i+1}: invalid rotation.")
        if lm.get("district") not in districts:
            errors.append(f"Landmark {i+1}: district does not exist.")
        elif _vector(lm.get("position"), 2):
            district_poly = next(d.get("polygon") for d in data["city_districts"] if isinstance(d, dict) and d.get("id") == lm["district"])
            if isinstance(district_poly, list) and all(_vector(p, 2) for p in district_poly) and not harbor.in_poly(lm["position"], district_poly):
                errors.append(f"Landmark {i+1}: building center must lie inside its named district.")
        if "floors" in lm and (not _number(lm["floors"]) or lm["floors"] != int(lm["floors"]) or not 1 <= lm["floors"] <= 14):
            errors.append(f"Landmark {i+1}: invalid floor count.")
        elif "floors" in lm and lm.get("design") in designs and not designs[lm["design"]]["floors"][0] <= lm["floors"] <= designs[lm["design"]]["floors"][1]:
            errors.append(f"Landmark {i+1}: floor count must stay within the building family bounds.")
    for i, p in enumerate(data.get("decor", [])):
        if not isinstance(p, dict):
            errors.append(f"Decor {i+1} must be an object.")
            continue
        point(p.get("position"), f"Decor {i+1}")
        if p.get("id") not in library:
            errors.append(f"Decor {i+1}: unknown asset id.")
        if p.get("domain", "land") not in ["land", "sea"]:
            errors.append(f"Decor {i+1}: domain must be land or sea.")
        expected_domain = "sea" if str(p.get("id", "")).split(".")[0] in {"small_boat", "barge"} else "land"
        if p.get("domain", "land") != expected_domain:
            errors.append(f"Decor {i+1}: {p.get('id')} must be supported by {expected_domain}.")
        if not _number(p.get("rotation_degrees", 0)):
            errors.append(f"Decor {i+1}: invalid rotation.")
        if p.get("id") == "freight_wagon.boxcar" and _vector(p.get("position"), 2):
            supported = False
            for line in (data.get("railways", []) if isinstance(data.get("railways", []), list) else []):
                if not isinstance(line, dict) or not isinstance(line.get("points"), list) or not all(_vector(v, 2) for v in line["points"]):
                    continue
                for a, b in zip(line["points"], line["points"][1:]):
                    yaw = harbor.yaw_of(harbor.sub(b, a))
                    offset = abs((float(p.get("rotation_degrees", 0))-yaw+90) % 180-90) if _number(p.get("rotation_degrees", 0)) else 180
                    if harbor.seg_dist(p["position"], a, b) <= .25 and offset <= 2:
                        supported = True
            if not supported:
                errors.append(f"Decor {i+1}: freight wagons must align with an authored railway.")

    objectives = sc.get("objectives", [])
    if not objectives or len(objectives) != len(sc.get("sectors", [])):
        errors.append("Each objective needs one sector name; at least one objective is required.")
    for i, p in enumerate(objectives):
        point(p, f"Objective {i+1}")
    # Operations use stable objective indices. Reject broken references before
    # the editor can save a mission whose logistics or victory gate cannot work.
    operation = sc.get("operation", {})
    if not isinstance(operation, dict):
        errors.append("scenario.operation must be an object.")
    else:
        def objective_index(value, label):
            if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value < len(objectives):
                errors.append(f"{label}: expected an existing objective index.")

        def index_list(values, label):
            if not isinstance(values, list):
                errors.append(f"{label}: expected an array of objective indices.")
                return
            if len({str(value) for value in values}) != len(values):
                errors.append(f"{label}: objective indices must be unique.")
            for value in values:
                objective_index(value, label)

        for key in ["kind", "title", "brief"]:
            if key in operation and not isinstance(operation[key], str):
                errors.append(f"operation.{key} must be text.")
        facilities = operation.get("facilities", [])
        if not isinstance(facilities, list):
            errors.append("operation.facilities must be an array.")
        else:
            for i, facility in enumerate(facilities):
                label = f"Facility {i+1}"
                if not isinstance(facility, dict):
                    errors.append(f"{label} must be an object.")
                    continue
                objective_index(facility.get("objective"), label)
                income = facility.get("income", 0)
                if not _number(income) or not 0 <= income <= 20:
                    errors.append(f"{label}: income must be between 0 and 20 supply per second.")
                if "forward_position" in facility:
                    point(facility["forward_position"], f"{label} forward insertion")
                if "requires_naval_control" in facility:
                    if not isinstance(facility["requires_naval_control"], bool):
                        errors.append(f"{label}: requires_naval_control must be true or false.")
                    elif facility["requires_naval_control"] and "naval_zone" not in operation:
                        errors.append(f"{label}: naval-controlled logistics require a naval control zone.")
        index_list(operation.get("deny_reserve_objectives", []), "Reserve route")
        if "reserve_delay" in operation:
            delay = operation["reserve_delay"]
            if not _number(delay) or not 0 <= delay <= 300:
                errors.append("operation.reserve_delay must be between 0 and 300 seconds.")
        if "naval_zone" in operation:
            zone = operation["naval_zone"]
            if not isinstance(zone, dict):
                errors.append("operation.naval_zone must be an object.")
            else:
                point(zone.get("position"), "Naval control zone")
                if "name" in zone and not isinstance(zone["name"], str):
                    errors.append("Naval control zone: name must be text.")
                if not _number(zone.get("radius")) or not 4 <= zone["radius"] <= 100:
                    errors.append("Naval control zone: radius must be between 4 and 100.")
                index_list(zone.get("requires_objectives", []), "Naval control prerequisites")
                if "sea" not in sc.get("available_domains", ["land", "air"]):
                    errors.append("A naval control zone requires sea units on this battlefield.")

    elevation = sc.get("elevation", [])
    if not isinstance(elevation, list) or len(elevation) > 16:
        errors.append("scenario.elevation must contain at most 16 plateau patches.")
    else:
        for i, patch in enumerate(elevation):
            label = f"Elevation {i+1}"
            if not isinstance(patch, dict):
                errors.append(f"{label} must be an object.")
                continue
            rect(patch.get("rect"), label)
            if not _number(patch.get("height")) or not 0 <= patch["height"] <= 40:
                errors.append(f"{label}: height must be between 0 and 40.")
            if not _number(patch.get("ramp")) or not 4 <= patch["ramp"] <= 120:
                errors.append(f"{label}: ramp width must be between 4 and 120.")
    if "elevation_mesh_step" in sc:
        step = sc["elevation_mesh_step"]
        if not _number(step) or not 1 <= step <= 4:
            errors.append("scenario.elevation_mesh_step must be between 1 and 4.")
    for key in ["field_insertion", "field_enemy_insertion"]:
        point(sc.get(key), key)
    if "field_sea_insertion" in sc:
        point(sc["field_sea_insertion"], "field_sea_insertion")
    for side in ["player_force", "enemy_force", "reserve_force"]:
        if not isinstance(sc.get(side, []), list):
            errors.append(f"{side} must be an array.")
            continue
        for i, u in enumerate(sc.get(side, [])):
            if not isinstance(u, dict):
                errors.append(f"{side} {i+1} must be an object.")
                continue
            point(u.get("position"), f"{side} {i+1}")
            if u.get("kind") not in ["rifle", "atgm", "tank", "aa", "engineer", "drone", "helo", "boat"]:
                errors.append(f"{side} {i+1}: unknown mobile unit.")
    if errors:
        return errors

    # Roads and rails must be physically supported. Check the complete width,
    # including caps, against polygon edges; never paint a road across water.
    coast = [edge for poly in water for edge in harbor.edges(poly)]
    for name, a, b, w in lines:
        r = w/2
        if any(harbor.in_poly(p, poly) for poly in water for p in [a, b]) or any(harbor.seg_seg_dist(a, b, c, d) < r-.001 for c, d in coast):
            errors.append(f"{name}: corridor overlaps water; route it around the coast (bridges are not implemented).")
        if min(a[0], b[0]) < r or min(a[1], b[1]) < r or max(a[0], b[0]) > width-r or max(a[1], b[1]) > height-r:
            errors.append(f"{name}: corridor width extends outside the map.")
        for rock in rocks:
            if harbor.poly_seg_dist(harbor.rect_poly(rock), a, b) < r+.12:
                errors.append(f"{name}: road or rail intersects a solid rock parcel.")
                break
    for i, rock in enumerate(rocks):
        if any(harbor.polys_touch(poly, harbor.rect_poly(rock)) for poly in water):
            errors.append(f"Rock parcel {i+1}: land feature intersects water.")
    return errors
