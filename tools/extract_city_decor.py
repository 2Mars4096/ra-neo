#!/usr/bin/env python3
"""Seed resources/assets_city.json from the decor table in docs/harbor-city-design.md.

Run once to create the contract; the decor builder may then refine descriptions.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATEGORY = {"tree": "vegetation", "lamp": "town_life", "trolley_pole": "street", "kiosk": "town_life",
            "monument": "town_life", "fountain": "town_life", "wall": "boundaries", "fence": "boundaries",
            "playground": "town_life", "laundry_line": "town_life", "heat_pipe": "industry", "parking": "street",
            "car": "vehicles", "van": "vehicles", "dumpster": "town_life", "portal_crane": "waterfront",
            "rail_siding": "industry", "freight_wagon": "industry", "tank": "industry", "container": "waterfront",
            "pergola": "rural", "greenhouse": "rural", "shed": "rural", "vineyard": "rural",
            "water_tower": "rural", "haystack": "rural", "bench": "town_life", "flowerbed": "town_life"}
ROW = re.compile(r"\| ([a-z_]+)\.([a-z_]+) \| \[([^\]]+)\] \| ([\d.]+) \| (\w+) \| ([^|]+) \|")

def main():
    doc = (ROOT / "docs/harbor-city-design.md").read_text()
    section = doc.split("## Decor ids")[1].split("## Battlefield engineers")[0]
    out = []
    for line in section.splitlines():
        m = ROW.match(line)
        if not m:
            continue
        kind, variant, foot, height, collision, placement = m.groups()
        out.append({"kind": kind, "variant": variant, "category": CATEGORY[kind],
                    "label": f"{kind} {variant}".replace("_", " ").capitalize(),
                    "footprint": [float(x) for x in foot.split(",")], "height": float(height),
                    "placement": [p.strip().replace(" ", "_") for p in placement.split(",")],
                    "collision": collision, "cover": False,
                    "description": "Harbor-city decor; see docs/harbor-city-design.md."})
    (ROOT / "resources/assets_city.json").write_text(json.dumps(out, indent=1) + "\n")
    print(f"{len(out)} decor specs")

if __name__ == "__main__":
    main()
