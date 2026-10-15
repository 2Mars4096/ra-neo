#!/usr/bin/env python3
"""Render the compiled Black Sea Harbor plan: districts, open spaces, roads,
oriented building footprints coloured by design family, decor dots.

Writes artifacts/harbor-layout.svg/.html and, when rsvg-convert is available,
artifacts/harbor-layout.png (2048 px wide). Optional --rects outlines the
collision rects; --crop x,z,w,h renders a detail view to harbor-layout.crop.png.
"""
import argparse, html, json, math, shutil, subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
FAMILY = {  # design -> fill colour by family
    "classic_row": "#e6cf9f", "classic_corner": "#f0d9a6", "stalin_block": "#d9b98a", "civic_hall": "#f4e7c8",
    "cathedral": "#fff5d6", "colonnade_landing": "#fff5d6", "market_hall": "#e9c27e",
    "panel_5": "#b9c3cc", "panel_9": "#98a6b3", "point_tower": "#7f8f9e", "school": "#d6a9a0", "kindergarten": "#e0b8ae",
    "shop_pavilion": "#9fc7c0", "stone_house": "#d98f6a", "outbuilding": "#b88a6c", "dacha_hut": "#c09a72",
    "garage_row": "#8c8a86", "transit_shed": "#7c8790", "workshop_hall": "#6f7a83", "port_admin": "#a3b1bd",
    "gatehouse": "#a3b1bd", "slipway": "#5e6a73", "barn_long": "#a77d58", "coop_shed": "#8f8a7c",
    "petrol_station": "#d0d38a", "barracks": "#8d9a72", "fort_ruin": "#9c9483", "rock": "#7f8f74"}
OPEN = {"square": "#cfc6ae", "cathedral_close": "#5d7a52", "hill_park": "#55724c", "seafront": "#5f7c56", "ravine": "#607a4b",
        "cemetery": "#4f6646", "scrub": "#7c7d5c", "tank_farm": "#8d8d84", "stockyard": "#8f9089", "parade": "#a59f8b",
        "vineyard": "#7d8a4a", "field": "#9b8a5c", "headland": "#5a6e4a", "sports": "#7e9a63"}
DISTRICT = {"perimeter": "#857f6d", "private": "#76734f", "garages": "#6e6c58", "green": "#6a7552", "port": "#7d7f7a",
            "superblock": "#7a7d6e", "village": "#77744b", "compound": "#71765c", "north": "#727251", "open": "#66704f"}
ROAD = {"boulevard": "#b9b29b", "avenue": "#aaa595", "arterial": "#9d9c93", "port": "#9a9b98", "street": "#a19c8c",
        "lane": "#9c9480", "garage": "#8f8b80", "track": "#8f8466"}

def decor_colour(pid):
    kind = pid.split(".")[0]
    if kind in ("tree", "orchard", "hedgerow", "broken_tree"): return "#2f5a2a"
    if kind in ("wall", "fence"): return "#4b3b2c"
    if kind in ("vineyard",): return "#3e5a22"
    if kind in ("car", "van", "pickup", "tractor", "farm_trailer", "freight_wagon"): return "#b03a2e"
    if kind in ("portal_crane", "gantry"): return "#d8a020"
    if kind in ("container", "pipe_stack", "tank"): return "#3d6f9a"
    if kind in ("rail_siding",): return "#5a4a3a"
    if kind in ("grass_patch", "flowerbed", "parking"): return "#9aa36b"
    return "#e8e0c8"

def pts(poly): return " ".join(f"{x:.2f},{y:.2f}" for x, y in poly)

def obb(e):
    (cx, cz), (W, D), yaw = e["position"], e["source_size"], math.radians(-float(e["rotation_degrees"]))
    ex, ez = (math.cos(yaw), math.sin(yaw)), (-math.sin(yaw), math.cos(yaw))
    return [(cx+sx*ex[0]*W/2+sz*ez[0]*D/2, cz+sx*ex[1]*W/2+sz*ez[1]*D/2) for sx, sz in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]

def render(s, show_rects=False, view=None):
    w, h = s["size"]; vb = view or [0, 0, w, h]
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb[0]} {vb[1]} {vb[2]} {vb[3]}" role="img" aria-label="Compiled Black Sea Harbor layout"><rect x="-10" y="-10" width="{w+20}" height="{h+20}" fill="#646b50"/>']
    for d in s.get("city_districts", []):
        svg.append(f'<polygon points="{pts(d["polygon"])}" fill="{DISTRICT.get(d["morphology"], "#666")}" fill-opacity="0.55"/>')
    for p in s["water_polygons"]: svg.append(f'<polygon points="{pts(p)}" fill="#294e60"/>')
    for r in s.get("woods", []): svg.append(f'<rect x="{r[0]}" y="{r[1]}" width="{r[2]}" height="{r[3]}" fill="#3e573e"/>')
    for o in s.get("open_spaces", []): svg.append(f'<polygon points="{pts(o["polygon"])}" fill="{OPEN.get(o["kind"], "#777")}" fill-opacity="0.85"/>')
    for c in s.get("courtyards", []): svg.append(f'<rect x="{c[0]}" y="{c[1]}" width="{c[2]}" height="{c[3]}" fill="#8e8a70" fill-opacity="0.6"/>')
    nodes = s["roads"]["nodes"]; cls = {}
    for e in s["roads"]["edges"]:
        a, b = nodes[e[0]], nodes[e[1]]
        svg.append(f'<path d="M {a[0]} {a[1]} L {b[0]} {b[1]}" fill="none" stroke="#8f8a7b" stroke-width="{e[2]}" stroke-linecap="round"/>')
    for p in s["map_props"]:
        if p["collision"] == "flat":
            r = p["bounds"]; svg.append(f'<rect x="{r[0]}" y="{r[1]}" width="{r[2]}" height="{r[3]}" fill="{decor_colour(p["id"])}" fill-opacity="0.7"/>')
    for e in s["architecture"]:
        fill = FAMILY.get(e["design"], "#c6b18e")
        stroke = "#2b2a25"
        if e.get("damage", 0) == 1: stroke = "#b5452b"
        if e.get("damage", 0) == 2: fill = "#6e5a4a"; stroke = "#d0482a"
        svg.append(f'<polygon points="{pts(obb(e))}" fill="{fill}" stroke="{stroke}" stroke-width="{0.9 if e.get("damage") else 0.35}"/>')
    if show_rects:
        for r in s["blocks"]: svg.append(f'<rect x="{r[0]}" y="{r[1]}" width="{r[2]}" height="{r[3]}" fill="none" stroke="#ff00ff" stroke-width="0.2"/>')
    for p in s["map_props"]:
        if p["collision"] == "flat": continue
        r = p["bounds"]; c = decor_colour(p["id"])
        if r[2]*r[3] > 4 and p["id"].split(".")[0] not in ("tree",):
            svg.append(f'<rect x="{r[0]}" y="{r[1]}" width="{r[2]}" height="{r[3]}" fill="{c}" fill-opacity="0.85"/>')
        else:
            svg.append(f'<circle cx="{r[0]+r[2]/2:.2f}" cy="{r[1]+r[3]/2:.2f}" r="{1.6 if p["id"].startswith("tree") else 0.9}" fill="{c}"/>')
    for label, p in zip(s["sectors"], s["objectives"]):
        svg.append(f'<circle cx="{p[0]}" cy="{p[1]}" r="9" fill="none" stroke="#edd879" stroke-width="2"/><text x="{p[0]+12}" y="{p[1]-9}" font-size="13" fill="#fff1bd" font-family="sans-serif">{html.escape(label)}</text>')
    for label, key in [("LAND ENTRY", "field_insertion"), ("SEA ENTRY", "field_sea_insertion")]:
        p = s[key]; svg.append(f'<circle cx="{p[0]}" cy="{p[1]}" r="8" fill="#a8d4cb"/><text x="{p[0]+13}" y="{p[1]+4}" font-size="13" fill="#e0fff5" font-family="sans-serif">{label}</text>')
    if view is None:
        y = 20
        for name in ["classic_row", "stalin_block", "panel_5", "panel_9", "stone_house", "garage_row", "transit_shed", "workshop_hall", "barn_long"]:
            svg.append(f'<rect x="8" y="{y-8}" width="10" height="8" fill="{FAMILY[name]}"/><text x="22" y="{y}" font-size="9" fill="#f2efe2" font-family="sans-serif">{name}</text>'); y += 12
        for d in s.get("city_districts", []):
            c = [sum(p[i] for p in d["polygon"])/len(d["polygon"]) for i in (0, 1)]
            svg.append(f'<text x="{c[0]:.0f}" y="{c[1]:.0f}" font-size="11" fill="#fffbe6" fill-opacity="0.75" font-family="sans-serif" text-anchor="middle">{html.escape(d["name"])}</text>')
    svg.append("</svg>")
    return "".join(svg)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--rects", action="store_true"); ap.add_argument("--crop", default="")
    args = ap.parse_args()
    s = next(x for x in json.loads((root/"resources/scenarios.json").read_text()) if x["id"] == "black_sea_harbor")
    out = root/"artifacts"
    tool = shutil.which("rsvg-convert")
    if args.crop:
        view = [float(v) for v in args.crop.split(",")]
        (out/"harbor-layout.crop.svg").write_text(render(s, True, view))
        if tool: subprocess.run([tool, "-w", "1600", str(out/"harbor-layout.crop.svg"), "-o", str(out/"harbor-layout.crop.png")], check=True)
        print("Crop written", view); return
    svg = render(s, args.rects)
    (out/"harbor-layout.svg").write_text(svg)
    (out/"harbor-layout.html").write_text('<!doctype html><meta charset="utf-8"><title>Black Sea Harbor layout</title><style>body{background:#18201e;color:#eee;font:16px system-ui;max-width:1500px;margin:auto;padding:24px}svg{width:100%;max-height:88vh}p{color:#bdc5b8}</style><h1>Black Sea Harbor — compiled layout preview</h1><p>1024 × 768 world units. Fictional Sevastopol-inspired geography. Oriented building footprints are coloured by design family; red outlines are damaged buildings; dots are decor. Authoritative map data, not a gameplay screenshot.</p>'+svg)
    if tool: subprocess.run([tool, "-w", "2048", str(out/"harbor-layout.svg"), "-o", str(out/"harbor-layout.png")], check=True)
    print("Layout preview written:", s["building_count"], "buildings,", len(s["map_props"]), "decor", "(png)" if tool else "(svg only)")

if __name__ == "__main__": main()
