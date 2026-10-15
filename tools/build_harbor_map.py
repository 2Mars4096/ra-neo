#!/usr/bin/env python3
"""Compile the fictional Black Sea Harbor blueprint into scenario data; stdlib only.

Pipeline (docs/harbor-city-design.md "Layout compiler rules"):
authored district streets -> planar block faces -> plots cut along block edges
with seeded lognormal widths -> one building per plot chosen by district
morphology (setback, orientation, corner/main-street/landmark rules) -> yards,
walls and decor per morphology -> damage clustered near objectives and the
freight front. Every random draw is seeded from a stable per-block/per-edge key.

Rotated buildings never use one large AABB: each oriented footprint becomes
<=6 axis-aligned collision rects that cover it with <=1 u excess. Where the
street angle cannot be decomposed that tightly, the building yaw is snapped
toward the nearest axis (a slightly stepped frontage, as on real slopes).

Run: python3 tools/build_harbor_map.py [--check]
--check verifies byte-for-byte reproducibility without writing scenarios.json.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
import re
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT = ROOT / "resources/maps/black_sea_harbor.json"
SCENARIOS = ROOT / "resources/scenarios.json"
MAP_W, MAP_H = 1024, 768
TOL = 0.95  # construction tolerance for collision excess (contract: <=1 u)
MAX_RECTS = 6

# ---------------------------------------------------------------- geometry
def sub(a, b): return (a[0]-b[0], a[1]-b[1])
def add(a, b): return (a[0]+b[0], a[1]+b[1])
def mul(a, k): return (a[0]*k, a[1]*k)
def dot(a, b): return a[0]*b[0]+a[1]*b[1]
def cross(a, b): return a[0]*b[1]-a[1]*b[0]
def length(a): return math.hypot(a[0], a[1])
def unit(a):
    l = length(a)
    return (a[0]/l, a[1]/l) if l > 1e-12 else (1.0, 0.0)
def left(d): return (-d[1], d[0])

def seg_dist(p, a, b):
    v = sub(b, a); L = dot(v, v)
    t = 0.0 if L < 1e-12 else max(0.0, min(1.0, dot(sub(p, a), v)/L))
    return length(sub(p, add(a, mul(v, t))))

def seg_hit(a, b, c, d, eps=1e-9):
    ab = sub(b, a); cd = sub(d, c); den = cross(ab, cd)
    if abs(den) < eps: return None
    t = cross(sub(c, a), cd)/den; u = cross(sub(c, a), ab)/den
    return (t, u) if -1e-9 <= t <= 1+1e-9 and -1e-9 <= u <= 1+1e-9 else None

def seg_seg_dist(a, b, c, d):
    if seg_hit(a, b, c, d): return 0.0
    return min(seg_dist(a, c, d), seg_dist(b, c, d), seg_dist(c, a, b), seg_dist(d, a, b))

def edges(poly): return zip(poly, poly[1:]+poly[:1])

def in_poly(p, poly):
    x, y = p; hit = False
    for a, b in edges(poly):
        if (a[1] > y) != (b[1] > y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]: hit = not hit
    return hit

def area(poly): return sum(cross(a, b) for a, b in edges(poly))/2

def centroid(poly):
    A = area(poly)
    if abs(A) < 1e-9: return (sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly))
    cx = sum((a[0]+b[0])*cross(a, b) for a, b in edges(poly))/(6*A)
    cz = sum((a[1]+b[1])*cross(a, b) for a, b in edges(poly))/(6*A)
    return (cx, cz)

def inside_convex(p, poly):
    s = None
    for a, b in edges(poly):
        c = cross(sub(b, a), sub(p, a))
        if abs(c) < 1e-12: continue
        if s is None: s = c > 0
        elif s != (c > 0): return False
    return True

def dist_convex(p, poly):
    if inside_convex(p, poly): return 0.0
    return min(seg_dist(p, a, b) for a, b in edges(poly))

def poly_seg_dist(poly, a, b):
    if inside_convex(a, poly) or inside_convex(b, poly): return 0.0
    return min(seg_seg_dist(a, b, c, d) for c, d in edges(poly))

def convex_sep(A, B):
    """Largest separating gap over SAT axes; negative means overlap depth."""
    best = -math.inf
    for poly in (A, B):
        for a, b in edges(poly):
            n = unit(left(sub(b, a)))
            pa = [dot(p, n) for p in A]; pb = [dot(p, n) for p in B]
            best = max(best, min(pb)-max(pa), min(pa)-max(pb))
    return best

def polys_touch(P, C):
    """General simple polygon P vs convex C: any overlap (borders count)."""
    if any(in_poly(p, P) for p in C) or any(inside_convex(p, C) for p in P): return True
    return any(seg_hit(a, b, c, d) for a, b in edges(P) for c, d in edges(C))

def rect_poly(r):
    x, z, w, d = r
    return [(x, z), (x+w, z), (x+w, z+d), (x, z+d)]

def bbox(poly):
    xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
    return (min(xs), min(zs), max(xs), max(zs))

def frame(yaw):
    """Godot yaw: local +x and +z axes in world (x,z). Street face is local -z."""
    a = math.radians(-yaw)
    return (math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))

def obb(c, W, D, yaw):
    ex, ez = frame(yaw)
    return [(c[0]+sx*ex[0]*W/2+sz*ez[0]*D/2, c[1]+sx*ex[1]*W/2+sz*ez[1]*D/2)
            for sx, sz in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]

def local_to_world(c, yaw, x, z):
    ex, ez = frame(yaw)
    return (c[0]+ex[0]*x+ez[0]*z, c[1]+ex[1]*x+ez[1]*z)

def aabb(local, position, yaw):
    pts = [local_to_world(position, yaw, x, z) for x, z in rect_poly(local)]
    low = [min(p[i] for p in pts) for i in [0, 1]]; high = [max(p[i] for p in pts) for i in [0, 1]]
    # Round outward; never shrink the rotated physical footprint.
    low = [math.floor(v*10000)/10000 for v in low]; high = [math.ceil(v*10000)/10000 for v in high]
    return [*low, round(high[0]-low[0], 4), round(high[1]-low[1], 4)]

def yaw_of(d): return -math.degrees(math.atan2(d[1], d[0]))

# ------------------------------------------------- oriented-footprint collision
def _clip(poly, axis, value, keep_below):
    out = []
    for a, b in edges(poly):
        ia = a[axis] <= value if keep_below else a[axis] >= value
        ib = b[axis] <= value if keep_below else b[axis] >= value
        if ia: out.append(a)
        if ia != ib:
            t = (value-a[axis])/(b[axis]-a[axis])
            out.append((a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t))
    return out

def obb_distance(P):
    """Closed-form point distance to an oriented rectangle given by 4 corners."""
    c = ((P[0][0]+P[2][0])/2, (P[0][1]+P[2][1])/2)
    ex = sub(P[1], P[0]); ez = sub(P[3], P[0]); hw = length(ex)/2; hd = length(ez)/2
    ex = unit(ex); ez = unit(ez)
    def dist(v):
        q = sub(v, c); x = abs(dot(q, ex))-hw; z = abs(dot(q, ez))-hd
        return math.hypot(max(x, 0.0), max(z, 0.0))
    return dist

def _strips(P, axis, lo, hi, limit, anchor=None, dist=None):
    """Greedy full-column strips along axis over [lo,hi]; coverage is exact by
    construction. anchor extends every strip to a fixed far side (cap mode)."""
    other = 1-axis; out = []; a = lo
    def rect(a, b):
        part = _clip(_clip(P, axis, a, False), axis, b, True)
        if not part: return None
        vals = [p[other] for p in part]+([anchor] if anchor is not None else [])
        return (a, b, min(vals), max(vals))
    def ok(r):
        if r is None: return False
        a, b, c0, c1 = r
        verts = [(a, c0), (a, c1), (b, c0), (b, c1)] if axis == 0 else [(c0, a), (c1, a), (c0, b), (c1, b)]
        return all(dist(v) <= TOL for v in verts)
    while a < hi-1e-9:
        if len(out) >= limit: return None
        r = rect(a, hi)
        if ok(r): out.append(r); break
        good, bad = a, hi
        for _ in range(26):
            mid = (good+bad)/2
            if ok(rect(a, mid)): good = mid
            else: bad = mid
        if good-a < 1e-3: return None
        out.append(rect(a, good)); a = good
    return [(r[0], r[2], r[1]-r[0], r[3]-r[2]) if axis == 0 else (r[2], r[0], r[3]-r[2], r[1]-r[0]) for r in out]

def _decompose(P):
    best = None; dist = obb_distance(P)
    for axis in (0, 1):
        vals = sorted(p[axis] for p in P)
        r = _strips(P, axis, vals[0], vals[-1], MAX_RECTS, dist=dist)
        if r and (best is None or len(r) < len(best)): best = r
        # Hybrid: middle strips along axis, end caps by perpendicular strips.
        for f in (0.0, 0.35, 0.7, 1.0):
            a = vals[0]+(vals[1]-vals[0])*f; b = vals[3]-(vals[3]-vals[2])*f
            if b-a < 1e-6: continue
            total = _strips(P, axis, a, b, MAX_RECTS, dist=dist)
            if not total: continue
            for cut, keep in ((a, True), (b, False)):
                cap = _clip(P, axis, cut, keep)
                if len(cap) < 3 or abs(area(cap)) < 1e-9: continue
                o = [p[1-axis] for p in cap]
                r = _strips(cap, 1-axis, min(o), max(o), MAX_RECTS, anchor=cut, dist=dist)
                if r is None: total = None; break
                total = total+r
            if not total or len(total) > MAX_RECTS: continue
            if all(all(dist(v) <= TOL for v in rect_poly(t)) for t in total):
                if best is None or len(total) < len(best): best = total
    return best if best and len(best) <= MAX_RECTS else None

_RECT_CACHE: dict = {}
def local_rects(W, D, yaw):
    """Collision rects relative to the building centre, or None if > 6 needed."""
    key = (round(W, 3), round(D, 3), round(yaw % 360, 3))
    if key not in _RECT_CACHE:
        off = (yaw+45) % 90-45
        if abs(off) < 1e-6:
            ex, _ = frame(yaw); w, d = (W, D) if abs(ex[0]) > 0.5 else (D, W)
            _RECT_CACHE[key] = [(-w/2, -d/2, w, d)]
        elif max(W, D)*abs(math.sin(2*math.radians(off)))/2 > MAX_RECTS+0.5:
            _RECT_CACHE[key] = None  # provably too many staircase steps
        else:
            _RECT_CACHE[key] = _decompose(obb((0.0, 0.0), W, D, yaw))
    return _RECT_CACHE[key]

def snap_yaw(W, D, yaw):
    """Closest decomposable yaw to the street yaw, moving toward the axis."""
    yaw = round(yaw, 2)
    base = round(yaw/90)*90; off = yaw-base
    if abs(off) < 0.3: return float(base), local_rects(W, D, base)
    r = local_rects(W, D, yaw)
    if r: return yaw, r
    sign = 1 if off > 0 else -1; lo, hi = 0.0, abs(off)
    for _ in range(7):
        mid = round((lo+hi)/2, 2)
        if local_rects(W, D, base+sign*mid): lo = mid
        else: hi = mid
    y = base+sign*lo
    return y, local_rects(W, D, y) if lo > 0 else local_rects(W, D, base)

def world_rects(c, rects):
    out = []
    for x, z, w, d in rects:
        x0 = math.floor((c[0]+x)*10000)/10000; z0 = math.floor((c[1]+z)*10000)/10000
        x1 = math.ceil((c[0]+x+w)*10000)/10000; z1 = math.ceil((c[1]+z+d)*10000)/10000
        out.append([x0, z0, round(x1-x0, 4), round(z1-z0, 4)])
    return out

# ------------------------------------------------------------ seeded random
class Rng:
    """splitmix64; seeded from a stable text key (never Python's hash())."""
    def __init__(self, *key):
        self.s = (zlib.crc32("|".join(str(k) for k in key).encode())*0x9E3779B97F4A7C15+0x632BE59BD9B4E019) & (2**64-1)
    def next(self):
        self.s = (self.s+0x9E3779B97F4A7C15) & (2**64-1); z = self.s
        z = ((z ^ (z >> 30))*0xBF58476D1CE4E5B9) & (2**64-1); z = ((z ^ (z >> 27))*0x94D049BB133111EB) & (2**64-1)
        return (z ^ (z >> 31))/2**64
    def uniform(self, a, b): return a+(b-a)*self.next()
    def chance(self, p): return self.next() < p
    def pick(self, items): return items[min(len(items)-1, int(self.next()*len(items)))]
    def int(self, a, b): return min(b, a+int(self.next()*(b-a+1)))
    def lognormal(self, median, sigma, lo, hi):
        u1 = max(1e-12, self.next()); u2 = self.next()
        z = math.sqrt(-2*math.log(u1))*math.cos(2*math.pi*u2)
        return max(lo, min(hi, median*math.exp(sigma*z)))
    def seed(self): return int(self.next()*2**31)

def stable_seed(*key): return zlib.crc32("|".join(str(k) for k in key).encode()) & 0x7FFFFFFF

# ------------------------------------------------------------ spatial index
class Grid:
    def __init__(self, cell=32.0): self.cell = cell; self.buckets = {}
    def keys(self, b):
        c = self.cell
        for x in range(int(math.floor(b[0]/c)), int(math.floor(b[2]/c))+1):
            for z in range(int(math.floor(b[1]/c)), int(math.floor(b[3]/c))+1): yield (x, z)
    def insert(self, b, item):
        for k in self.keys(b): self.buckets.setdefault(k, []).append(item)
    def query(self, b):
        seen = {}; out = []
        for k in self.keys(b):
            for item in self.buckets.get(k, []):
                if id(item) not in seen: seen[id(item)] = 1; out.append(item)
        return out

def grow(b, m): return (b[0]-m, b[1]-m, b[2]+m, b[3]+m)

# --------------------------------------------------------------- city model
def load_designs():
    text = (ROOT/"scripts/city_buildings.gd").read_text()
    rows = re.findall(r'"(\w+)":\{"builder":"\w+","w":\[([\d.]+),([\d.]+)\],"d":\[([\d.]+),([\d.]+)\],"floors":\[(\d+),(\d+)\]\}', text)
    return {r[0]: {"w": (float(r[1]), float(r[2])), "d": (float(r[3]), float(r[4])), "floors": (int(r[5]), int(r[6]))} for r in rows}

def load_library():
    library = {}
    for bundle in ["city", "street", "rural", "waterfront", "battlefield"]:
        for spec in json.loads((ROOT/f"resources/assets_{bundle}.json").read_text()):
            library[spec["kind"]+"."+spec["variant"]] = spec
    # This legacy quay is registered by assets_existing.gd from roadside_props.gd.
    library["quay_bay.existing"] = {"footprint": [-.6, -6, 1.1, 12], "collision": "solid", "placement": ["shared_roadside_footprint"]}
    return library

class City:
    def __init__(self, bp):
        self.bp = bp; self.sc = bp["scenario"]; self.rock_rects = bp["rock_parcels"]
        self.designs = load_designs(); self.library = load_library()
        self.water = self.sc["water_polygons"]
        self.coast = Grid(32)
        for poly in self.water:
            for a, b in edges(poly): self.coast.insert(grow(bbox([a, b]), 1), (tuple(a), tuple(b)))
        self.roads = []; self.road_grid = Grid(32)
        self.buildings = []; self.bgrid = Grid(32)
        self.plots = []; self.pgrid = Grid(32)
        self.props = []; self.prop_grid = Grid(32)
        self.reserve_polys = []; self.rgrid = Grid(32)
        self.circles = []
        self.districts = [dict(d, polygon=[tuple(p) for p in d["polygon"]]) for d in bp["city_districts"]]
        self.open_spaces = [dict(o, polygon=[tuple(p) for p in o["polygon"]]) for o in bp["open_spaces"]]
        self.morph = {d["id"]: d["morphology"] for d in self.districts}
        self.courtyards = []; self.blocks_out = []; self.queue = []

    # -- lookups
    def district_at(self, p):
        for d in self.districts:
            if in_poly(p, d["polygon"]): return d["id"]
        return None
    def is_water(self, p): return any(in_poly(p, poly) for poly in self.water)
    def coast_dist(self, poly, limit):
        best = math.inf
        for a, b in self.coast.query(grow(bbox(poly), limit)):
            best = min(best, poly_seg_dist(poly, a, b) if len(poly) > 2 else seg_seg_dist(poly[0], poly[1], a, b))
        return best
    def land_ok(self, poly, margin=1.5):
        b = bbox(poly)
        if b[0] < 2 or b[1] < 2 or b[2] > MAP_W-2 or b[3] > MAP_H-2: return False
        if any(self.is_water(p) for p in poly+[centroid(poly)]): return False
        return self.coast_dist(poly, margin+1) >= margin
    def road_gap(self, poly, ignore=()):
        """Smallest distance from poly to any road edge (negative = on road)."""
        best = math.inf
        for r in self.road_grid.query(grow(bbox(poly), 24)):
            if r["street"] in ignore: continue
            best = min(best, poly_seg_dist(poly, r["a"], r["b"])-r["w"]/2)
        return best
    def opposite_gap(self, p, n, street, maxd=80.0):
        """Distance along n from p to the nearest other road edge (back-to-back plots split it)."""
        t = 1.0
        while t < maxd:
            q = add(p, mul(n, t))
            for r in self.road_grid.query((q[0]-1, q[1]-1, q[0]+1, q[1]+1)):
                if r["street"] != street and seg_dist(q, r["a"], r["b"]) <= r["w"]/2: return t
            t += 1.0
        return math.inf
    def street_gap(self, poly, street):
        return min(poly_seg_dist(poly, r["a"], r["b"])-r["w"]/2 for r in self.roads if r["street"] == street)
    def reserved(self, poly, kinds_ok=()):
        for c, r in self.circles:
            if dist_convex(c, poly) < r: return True
        for item in self.rgrid.query(bbox(poly)):
            if item["kind"] in kinds_ok: continue
            if polys_touch(item["polygon"], poly): return True
        return False
    def building_clash(self, poly, gap):
        for other in self.bgrid.query(grow(bbox(poly), gap+1)):
            if convex_sep(poly, other["poly"]) < gap: return True
        return False
    def plot_clash(self, poly, own=None, gap=-0.01):
        for other in self.pgrid.query(grow(bbox(poly), 1)):
            if other is own: continue
            if convex_sep(poly, other["poly"]) < gap: return True
        return False
    def prop_clash(self, rect, pad=0.05):
        b = (rect[0]-pad, rect[1]-pad, rect[0]+rect[2]+pad, rect[1]+rect[3]+pad)
        for p in self.prop_grid.query(b):
            if p["solid"] and p["bounds"][0] < b[2] and b[0] < p["bounds"][0]+p["bounds"][2] and p["bounds"][1] < b[3] and b[1] < p["bounds"][1]+p["bounds"][3]: return True
        return False

    # -- buildings
    def place(self, design, front, d_street, W, D, setback, district, street=None, gap=0.3,
              face=None, kinds_ok=(), plot=None, fixed=None, floors=None, variant=None, rng=None,
              road_clear=0.5, coast=1.5, extra=None, check_plots=True):
        """front: point on the frontage line (road edge + setback reference) at
        plot mid; d_street: street direction (face/plot on its left)."""
        spec = self.designs.get(design)
        rng = rng or Rng(design, front)
        if fixed is not None:
            c, yaw = fixed; yaw, rects = snap_yaw(W, D, yaw)
            if rects is None: return None
        else:
            n = left(d_street)
            ex0, ez0 = frame(yaw_of(d_street))
            rough = obb(add(add(front, mul(n, setback)), mul(ez0, D/2)), W, D, yaw_of(d_street))
            self.why = 'road'
            if self.road_gap(rough) < road_clear-1.0: return None
            self.why = 'building'
            if self.building_clash(rough, gap-1.0): return None
            self.why = 'land'
            if not self.land_ok(rough, coast-1.0): return None
            yaw, rects = snap_yaw(W, D, yaw_of(d_street))
            if rects is None: return None
            ex, ez = frame(yaw)
            c = add(add(front, mul(n, setback)), mul(ez, D/2))
            poly = obb(c, W, D, yaw)
            ahead = max(-dot(sub(p, front), n) for p in poly)-(-setback)
            if ahead > 1e-6: c = add(c, mul(n, ahead))  # snapped corner stays behind the line
        poly = obb(c, W, D, yaw)
        self.why = 'land'
        if not self.land_ok(poly, coast): return None
        self.why = 'road'
        if self.road_gap(poly) < road_clear: return None
        wr = world_rects(c, rects)
        deficit = 0.06-min(self.road_gap(rect_poly(r)) for r in wr)
        if deficit > 0:
            # Staircase excess may poke into the sidewalk: step the whole building back.
            if fixed is not None or deficit > 1.6: return None
            c = add(c, mul(left(d_street), deficit+0.02)); poly = obb(c, W, D, yaw); wr = world_rects(c, rects)
            if min(self.road_gap(rect_poly(r)) for r in wr) < 0.05: return None
            if not self.land_ok(poly, coast): return None
        self.why = 'building'
        if self.building_clash(poly, gap): return None
        self.why = 'reserved'
        if self.reserved(poly, kinds_ok): return None
        self.why = 'face'
        if face is not None and not all(in_poly(p, face) for p in poly): return None
        self.why = 'plot'
        if check_plots and self.plot_clash(poly, own=plot, gap=0.0): return None
        f = spec["floors"] if spec else (1, 1)
        entry = {"design": design, "position": [round(c[0], 4), round(c[1], 4)], "rotation_degrees": round(yaw, 4),
                 "source_size": [round(W, 3), round(D, 3)],
                 "floors": floors if floors is not None else rng.int(f[0], f[1]),
                 "variant": variant if variant is not None else rng.int(0, 3), "palette": rng.int(0, 3),
                 "damage": 0, "seed": stable_seed(design, round(c[0], 2), round(c[1], 2)), "district": district,
                 "morphology": self.morph.get(district, "landmark"), "poly": poly, "rects": wr}
        if street: entry["street"] = street
        if extra: entry.update(extra)
        self.buildings.append(entry); self.bgrid.insert(bbox(poly), entry)
        return entry

    def size(self, design, rng, wmed=None, sigma=0.25, wmax=None):
        s = self.designs[design]
        hi = s["w"][1] if wmax is None else min(s["w"][1], wmax)
        if hi < s["w"][0]: return None
        W = rng.lognormal(wmed or (s["w"][0]+s["w"][1])/2, sigma, s["w"][0], hi)
        D = round(rng.uniform(*s["d"])*2)/2
        if design == "garage_row": return round(3.2*max(6, min(24, int(W/3.2))), 2), D
        return round(W*2)/2, D

    # -- props
    def prop(self, asset, p, yaw=0.0, context="", domain="land", group=None, road_margin=0.5, district=None, allow_reserved=False):
        if self.queue is not None:
            # Building phase: yards are decorated only after every building exists.
            self.queue.append((asset, p, yaw, context, domain, group, road_margin, district, allow_reserved)); return None
        spec = self.library[asset]; r = aabb(spec["footprint"], p, yaw)
        flat = spec["collision"] == "flat"
        poly = rect_poly(r)
        if r[0] < 1 or r[1] < 1 or r[0]+r[2] > MAP_W-1 or r[1]+r[3] > MAP_H-1: return None
        samples = poly+[(r[0]+r[2]/2, r[1]+r[3]/2)]
        if any(self.is_water(q) != (domain == "sea") for q in samples): return None
        for rr in self.rock_rects:
            if rr[0] < r[0]+r[2]+0.05 and r[0] < rr[0]+rr[2]+0.05 and rr[1] < r[1]+r[3]+0.05 and r[1] < rr[1]+rr[3]+0.05: return None
        for b in self.bgrid.query(grow(bbox(poly), 1)):
            if any(rr[0] < r[0]+r[2]+0.05 and r[0] < rr[0]+rr[2]+0.05 and rr[1] < r[1]+r[3]+0.05 and r[1] < rr[1]+rr[3]+0.05 for rr in b["rects"]): return None
            if convex_sep(poly, b["poly"]) < 0.05: return None
        if domain == "land" and not flat and self.road_gap(poly) < road_margin: return None
        if not allow_reserved:
            for c, rad in self.circles:
                if dist_convex(c, poly) < rad*0.7: return None
        if not flat:
            pad = 0.05
            for q in self.prop_grid.query((r[0]-pad, r[1]-pad, r[0]+r[2]+pad, r[1]+r[3]+pad)):
                if not q["solid"]: continue
                if group and q.get("group") == group: continue
                qb = q["bounds"]
                if qb[0] < r[0]+r[2]+pad and r[0] < qb[0]+qb[2]+pad and qb[1] < r[1]+r[3]+pad and r[1] < qb[1]+qb[3]+pad: return None
        item = {"id": asset, "position": [round(p[0], 5), round(p[1], 5)], "rotation_degrees": round(yaw, 6), "bounds": r,
                "domain": domain, "cover": False, "collision": spec["collision"], "context": context,
                "placement_tags": spec["placement"], "solid": not flat, "group": group,
                "district": district or self.district_at(p) or "open"}
        self.props.append(item); self.prop_grid.insert((r[0], r[1], r[0]+r[2], r[1]+r[3]), item)
        return item

    def prop_line(self, asset, a, b, context, group, inset=0.0, yaw_extra=0.0, district=None):
        """Wall/fence segments along a line; footprint long axis is local x."""
        span = length(sub(b, a))
        seg = self.library[asset]["footprint"][2]
        n = int((span-2*inset+0.01)//seg)
        if n <= 0: return 0
        d = unit(sub(b, a)); start = inset+(span-2*inset-n*seg)/2; placed = 0
        for i in range(n):
            p = add(a, mul(d, start+seg*(i+0.5)))
            if self.prop(asset, p, yaw_of(d)+yaw_extra, context, group=group, district=district): placed += 1
        return placed

# ------------------------------------------------------- street graph/faces
def build_graph(city):
    streets = []
    for si, st in enumerate(city.bp["streets"]):
        streets.append({"i": si, "name": st["name"], "w": float(st["width"]), "cls": st.get("class", "street"),
                        "purpose": st["purpose"], "pts": [tuple(map(float, p)) for p in st["points"]]})
    # T-junction snapping: street ends within 2.5 u of another street join it.
    for st in streets:
        for end in (0, -1):
            p = st["pts"][end]; best = None
            for other in streets:
                if other is st: continue
                for a, b in zip(other["pts"], other["pts"][1:]):
                    v = sub(b, a); t = max(0.0, min(1.0, dot(sub(p, a), v)/dot(v, v))); q = add(a, mul(v, t))
                    dd = length(sub(p, q))
                    if dd < 2.5 and (best is None or dd < best[0]): best = (dd, q)
            if best and best[0] > 1e-9: st["pts"][end] = best[1]
    segs = []
    for st in streets:
        for k, (a, b) in enumerate(zip(st["pts"], st["pts"][1:])): segs.append({"st": st, "k": k, "a": a, "b": b, "ts": [0.0, 1.0]})
    for i, s in enumerate(segs):
        for t in segs[i+1:]:
            if s["st"] is t["st"] and abs(s["k"]-t["k"]) <= 1: continue
            hit = seg_hit(s["a"], s["b"], t["a"], t["b"])
            if hit: s["ts"].append(min(1, max(0, hit[0]))); t["ts"].append(min(1, max(0, hit[1])))
    nodes = []; node_grid = {}
    def node(p):
        key = (round(p[0]), round(p[1]))
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for idx in node_grid.get((key[0]+dx, key[1]+dz), []):
                    if length(sub(nodes[idx], p)) < 0.05: return idx
        nodes.append(p); node_grid.setdefault(key, []).append(len(nodes)-1)
        return len(nodes)-1
    edges_out = {}
    for s in segs:
        ts = sorted(set(round(t, 9) for t in s["ts"]))
        ids = [node(add(s["a"], mul(sub(s["b"], s["a"]), t))) for t in ts]
        for u, v in zip(ids, ids[1:]):
            if u == v: continue
            key = (min(u, v), max(u, v))
            if key not in edges_out or edges_out[key]["w"] < s["st"]["w"]:
                edges_out[key] = {"u": u, "v": v, "w": s["st"]["w"], "street": s["st"]["name"], "cls": s["st"]["cls"]}
    out = {}
    for e in edges_out.values():
        for u, v in ((e["u"], e["v"]), (e["v"], e["u"])):
            out.setdefault(u, []).append(v)
    for u in out:
        out[u].sort(key=lambda v: math.atan2(nodes[v][1]-nodes[u][1], nodes[v][0]-nodes[u][0]))
    seen = set(); faces = []
    for u in out:
        for v in out[u]:
            if (u, v) in seen: continue
            walk = []; a, b = u, v
            while (a, b) not in seen:
                seen.add((a, b)); e = edges_out[(min(a, b), max(a, b))]
                walk.append({"a": nodes[a], "b": nodes[b], "w": e["w"], "street": e["street"], "cls": e["cls"], "u": a, "v": b})
                ring = out[b]; i = ring.index(a); a, b = b, ring[i-1]
            poly = [h["a"] for h in walk]
            faces.append({"halfedges": walk, "poly": poly, "area": area(poly)})
    return streets, nodes, edges_out, faces

# ---------------------------------------------------------------- morphology
SETBACK = {"boulevard": 3.2, "avenue": 3.2, "arterial": 3.0, "street": 0.8, "lane": 0.6, "port": 5.5, "track": 2.0, "garage": 1.5}

def frontage(city, h, face_poly, morphology, district, cursor_step=1.5):
    """Cut plots along one half-edge (face on its left) and build them."""
    a, b = h["a"], h["b"]; L = length(sub(b, a))
    if L < 8: return
    d = unit(sub(b, a)); n = left(d); w = h["w"]
    rng = Rng("edge", h["street"], round(a[0], 1), round(a[1], 1), round(b[0], 1), round(b[1], 1))
    cls = h["cls"]; s = 2.0
    if morphology == "perimeter": _perimeter_edge(city, h, face_poly, district, rng, a, d, n, w, L, cls)
    elif morphology in ("private", "north"): _private_edge(city, h, district, rng, a, d, n, w, L, village=False)
    elif morphology == "dacha": _private_edge(city, h, district, rng, a, d, n, w, L, village=False, dacha=True)
    elif morphology == "village": _private_edge(city, h, district, rng, a, d, n, w, L, village=True)
    elif morphology == "garages": _garage_edge(city, h, district, rng, a, d, n, w, L)
    elif morphology == "port": _port_edge(city, h, face_poly, district, rng, a, d, n, w, L)
    elif morphology == "superblock" and cls in ("arterial", "avenue"): _shop_edge(city, h, district, rng, a, d, n, w, L)
    elif morphology == "superblock" and cls == "garage": _garage_edge(city, h, district, rng, a, d, n, w, L)

def _perimeter_edge(city, h, face_poly, district, rng, a, d, n, w, L, cls):
    sb = SETBACK.get(cls, 0.8)
    main = cls in ("avenue", "boulevard")
    s = 1.0
    while s < L-6:
        if rng.chance(0.04) and s > 12:
            s += rng.uniform(6.5, 9.0); continue  # rare passage/vacant lot into the courtyard
        design = "classic_row"
        if main and rng.chance(0.28): design = "stalin_block"
        size = city.size(design, rng, wmed=12.5 if design == "classic_row" else 44.0, sigma=0.3, wmax=L-s-1)
        if size is None:
            design = "classic_row"; size = city.size(design, rng, wmed=13.0, sigma=0.2, wmax=L-s-1)
            if size is None: break
        W0, D = size; placed = None
        lo = city.designs[design]["w"][0]
        for W in sorted({W0, max(lo, round(W0*0.75*2)/2), max(lo, 12.0), lo}, reverse=True):
            if design == "stalin_block" and W < 36: continue
            front = add(add(a, mul(d, s+W/2)), mul(n, w/2))
            # Party walls: neighbours touch (gap 0) so the street reads as one frontage.
            placed = city.place(design, front, d, W, D, sb, district, street=h["street"], gap=0.0, face=face_poly,
                                rng=rng, variant=(1 if main and rng.chance(0.6) else rng.int(0, 3)),
                                extra={"ground_floor": "shops"} if main else None)
            if placed: break
        if placed: s += W+0.02
        else: s += 0.5

def perimeter_fill(city, h, face_poly, district):
    """Second pass: close remaining frontage gaps with the widest row that fits,
    so perimeter blocks read as continuous street walls with corner closures."""
    a, b = h["a"], h["b"]; L = length(sub(b, a))
    if L < 12: return
    d = unit(sub(b, a)); n = left(d); w = h["w"]
    rng = Rng("fill", h["street"], round(a[0], 1), round(a[1], 1))
    sb = SETBACK.get(h["cls"], 0.8)
    s = 0.5
    while s < L-5:
        placed = None
        for W in (22.0, 18.0, 15.0, 12.5, 10.0):
            if s+W > L-0.5: continue
            D = round(rng.uniform(9.0, 12.0)*2)/2
            front = add(add(a, mul(d, s+W/2)), mul(n, w/2))
            placed = city.place("classic_row", front, d, W, D, sb, district, street=h["street"], gap=0.0, face=face_poly,
                                rng=rng, variant=rng.int(0, 3))
            if placed: s += W+0.02; break
        if not placed: s += 0.5

def corner_buildings(city, face, district):
    hs = face["halfedges"]
    for i, h in enumerate(hs):
        prev = hs[i-1]
        if prev["street"] == h["street"] and abs(cross(unit(sub(prev["b"], prev["a"])), unit(sub(h["b"], h["a"])))) < 0.5: continue
        d0 = unit(sub(prev["b"], prev["a"])); d1 = unit(sub(h["b"], h["a"]))
        turn = math.degrees(math.atan2(cross(d0, d1), dot(d0, d1)))
        if not 55 <= turn <= 125: continue
        if city.district_at(h["a"]) is None: continue
        rng = Rng("corner", round(h["a"][0], 1), round(h["a"][1], 1))
        sb0 = SETBACK.get(prev["cls"], 0.8); sb1 = SETBACK.get(h["cls"], 0.8)
        p0 = add(prev["a"], mul(left(d0), prev["w"]/2+sb0)); p1 = add(h["a"], mul(left(d1), h["w"]/2+sb1))
        den = cross(d0, d1)
        t = cross(sub(p1, p0), d1)/den; K = add(p0, mul(d0, t))
        if rng.chance(0.08): continue  # occasional bombed-out/vacant corner lot
        for W, D in ((rng.uniform(15, 21.5), rng.uniform(14, 18)), (14.5, 14.0)):
            W, D = round(W*2)/2, round(D*2)/2
            yaw, rects = snap_yaw(W, D, yaw_of(d1))
            if rects is None: continue
            ex, ez = frame(yaw)
            e = None
            # Oblique junctions: nudge the corner inward until it clears both carriageways.
            for push in (0.2, 0.8, 1.4, 2.0):  # stays within the 5.5 u frontage setback
                for px, pz in ((push, push), (push, 0.2), (0.2, push)):
                    c = add(add(K, mul(ex, W/2+px)), mul(ez, D/2+pz))
                    probe = obb(c, W, D, yaw)
                    if max(city.street_gap(probe, prev["street"]), city.street_gap(probe, h["street"])) > 5.4: continue
                    e = city.place("classic_corner", None, None, W, D, 0, district, street=h["street"], gap=0.0, face=face["poly"],
                                   fixed=(c, yaw), rng=rng, extra={"corner_streets": [prev["street"], h["street"]]})
                    if e: break
                if e: break
            if e: break

def _private_edge(city, h, district, rng, a, d, n, w, L, village, dacha=False):
    s = 2.0
    pmin = 18 if village else (10 if dacha else 11.5)
    while s < L-pmin+1:
        pw = rng.lognormal(23.0 if village else (11.5 if dacha else 14.5), 0.2, pmin, 30 if village else (15 if dacha else 21))
        if s+pw > L-1: pw = L-1-s
        if pw < pmin: break
        p0 = add(add(a, mul(d, s)), mul(n, w/2+0.3)); p1 = add(p0, mul(d, pw))
        plot = None
        mid = add(p0, mul(d, pw/2)); cap = (city.opposite_gap(mid, n, h["street"])-0.6)/2
        cap = min(cap, (city.opposite_gap(p0, n, h["street"])-0.6)/2+2, (city.opposite_gap(p1, n, h["street"])-0.6)/2+2)
        for depth in ((38, 32, 26, 22, 18) if village else ((16, 14, 12) if dacha else (30, 26, 22, 18, 15, 13))):
            depth = min(depth, rng.uniform(depth-3, depth)) if depth > 16 else depth
            if depth > cap and depth > (11 if dacha else 13): continue
            poly = [p0, p1, add(p1, mul(n, depth)), add(p0, mul(n, depth))]
            if not city.land_ok(poly, 1.0) or city.road_gap(poly) < 0.2: continue
            if city.plot_clash(poly) or city.building_clash(poly, 0.3) or city.reserved(poly): continue
            if city.district_at(centroid(poly)) != district: continue
            plot = {"poly": poly, "depth": depth, "width": pw, "district": district}
            break
        if plot is None: s += 3.0; continue
        city.plots.append(plot); city.pgrid.insert(bbox(plot["poly"]), plot)
        if dacha:
            house = _dacha_plot(city, h, plot, rng, p0, d, n, pw, plot["depth"], district)
        else:
            house = _plot_house(city, h, plot, rng, p0, d, n, pw, plot["depth"], village, district)
            if house: _plot_yard(city, plot, house, rng, p0, d, n, pw, plot["depth"], village, district)
        s += pw

def _plot_house(city, h, plot, rng, p0, d, n, pw, depth, village, district):
    corner_right = rng.chance(0.5)
    design = "stone_house"
    W, D = city.size(design, rng, wmed=9.5 if village else 8.5, sigma=0.15, wmax=pw-3)
    sb = rng.uniform(0.6, 3.5) if not village else rng.uniform(2.0, 6.0)
    off = (pw-W-1.2) if corner_right else 1.2
    front = add(p0, mul(d, off+W/2))
    e = city.place(design, add(front, mul(n, -0.3)), d, W, D, sb+0.3, district, street=h["street"], gap=0.6, plot=plot, rng=rng)
    if e is None:
        off = 1.2 if corner_right else (pw-W-1.2)
        e = city.place(design, add(add(p0, mul(d, off+W/2)), mul(n, -0.3)), d, W, D, sb+0.3, district, street=h["street"], gap=0.6, plot=plot, rng=rng)
        corner_right = not corner_right
    if e is None: return None
    e["plot_corner"] = "right" if corner_right else "left"
    # Rear outbuilding / summer kitchen or barn on the opposite side.
    if village and depth >= 30 and pw >= 22 and rng.chance(0.55):
        bw = min(26.0, pw-2.0); bw = max(24.0, bw)
        if bw <= pw-1.5:
            back = add(p0, mul(d, pw/2)); city.place("barn_long", back, d, bw, rng.uniform(10, 11), depth-12.5, district, gap=0.6, plot=plot, rng=rng)
    elif rng.chance(0.75):
        kind = "dacha_hut" if rng.chance(0.3) else "outbuilding"
        OW, OD = city.size(kind, rng, sigma=0.2)
        side = 1.2 if corner_right else pw-OW-1.2
        back = add(p0, mul(d, side+OW/2))
        city.place(kind, back, d, OW, OD, depth-OD-1.2, district, gap=0.5, plot=plot, rng=rng)
        if pw >= 14 and depth >= 18 and rng.chance(0.55):  # summer kitchen beside the house
            OW, OD = city.size("outbuilding", rng, sigma=0.2)
            side = pw-OW-1.2 if corner_right else 1.2
            city.place("outbuilding", add(p0, mul(d, side+OW/2)), d, OW, OD, depth*0.5, district, gap=0.5, plot=plot, rng=rng)
    return e

def _dacha_plot(city, h, plot, rng, p0, d, n, pw, depth, district):
    """Soviet dacha cooperative: a small hut, picket fence, vegetable beds."""
    W, D = city.size("dacha_hut", rng, sigma=0.15, wmax=pw-2.5)
    off = rng.uniform(1.2, max(1.3, pw-W-1.2))
    e = city.place("dacha_hut", add(add(p0, mul(d, off+W/2)), mul(n, -0.3)), d, W, D, rng.uniform(1.5, 3.5), district, street=h["street"], gap=0.5, plot=plot, rng=rng)
    if e is None: return None
    yaw = yaw_of(d); group = "plot%d" % id(plot)
    city.prop_line("fence.picket", add(add(p0, mul(d, 0.2)), mul(n, 0.4)), add(add(p0, mul(d, pw-0.2)), mul(n, 0.4)), "dacha plot fence", group, district=district)
    city.prop_line("fence.picket", add(add(p0, mul(d, pw-0.3)), mul(n, 1.0)), add(add(p0, mul(d, pw-0.3)), mul(n, depth-0.3)), "dacha plot fence", group, district=district)
    for k in range(rng.int(0, 2)):
        city.prop(rng.pick(["greenhouse.film", "shed.small", "orchard.trained_row", "grass_patch.short_sward", "tree.acacia"]),
                  add(add(p0, mul(d, rng.uniform(2, pw-2))), mul(n, rng.uniform(depth*0.55, depth-2))), yaw, "dacha vegetable plot", district=district)
    return e

def _plot_yard(city, plot, house, rng, p0, d, n, pw, depth, village, district):
    group = "plot%d" % id(plot)
    wall = "fence.picket" if village else "wall.stone_yard"
    yaw = yaw_of(d)
    # Front wall with a gate where the house does not form the street wall.
    hp = house["poly"]; hx = sorted(dot(sub(p, p0), d) for p in hp)
    front_gap = min(dot(sub(p, p0), n) for p in hp)
    line_off = 0.95  # wall face stays outside the lane's clear edge
    segs = [(0.0, pw)]
    if front_gap < 2.0: segs = [(0.0, hx[0]-0.4), (hx[-1]+0.4, pw)]
    gate_done = False
    for lo, hi in segs:
        if hi-lo < 3.4: continue
        if not gate_done and hi-lo > 7:
            g = lo+(hi-lo)*rng.uniform(0.3, 0.7)
            city.prop("wall.stone_gate" if not village else "fence.picket", add(add(p0, mul(d, g)), mul(n, line_off)), yaw, "yard gate on lane", group=group, district=district)
            gate_done = True
            city.prop_line(wall, add(add(p0, mul(d, lo)), mul(n, line_off)), add(add(p0, mul(d, g-1.7)), mul(n, line_off)), "front yard wall", group, district=district)
            city.prop_line(wall, add(add(p0, mul(d, g+1.7)), mul(n, line_off)), add(add(p0, mul(d, hi)), mul(n, line_off)), "front yard wall", group, district=district)
        else:
            city.prop_line(wall, add(add(p0, mul(d, lo)), mul(n, line_off)), add(add(p0, mul(d, hi)), mul(n, line_off)), "front yard wall", group, district=district)
    # One shared side line per plot plus the rear line.
    side_a = add(add(p0, mul(d, pw-0.35)), mul(n, 1.0)); side_b = add(add(p0, mul(d, pw-0.35)), mul(n, depth-0.4))
    city.prop_line(wall, side_a, side_b, "plot boundary wall", group, district=district)
    city.prop_line(wall, add(add(p0, mul(d, 0.6)), mul(n, depth-0.4)), add(add(p0, mul(d, pw-0.6)), mul(n, depth-0.4)), "rear plot wall", group, district=district)
    # Garden: pergola by the house, fruit trees and greenhouse at the rear.
    hc = house["position"]
    if not village and rng.chance(0.55):
        city.prop("pergola.grape", add(add((hc[0], hc[1]), mul(n, house["source_size"][1]/2+2.6)), mul(d, rng.uniform(-1.5, 1.5))), yaw, "vine pergola over house terrace", district=district)
    for k in range(rng.int(1, 3)):
        p = add(add(p0, mul(d, rng.uniform(2.5, pw-2.5))), mul(n, rng.uniform(depth*0.55, depth-2.5)))
        city.prop("tree.acacia" if rng.chance(0.4) else "orchard.trained_row", p, yaw if k % 2 else yaw+90, "garden fruit tree", district=district)
    if rng.chance(0.3 if not village else 0.15):
        city.prop("greenhouse.film", add(add(p0, mul(d, rng.uniform(3, pw-3))), mul(n, depth*rng.uniform(0.5, 0.75))), yaw+90, "garden greenhouse", district=district)
    if rng.chance(0.3):
        city.prop("shed.small", add(add(p0, mul(d, rng.uniform(2.5, pw-2.5))), mul(n, depth-2.4)), yaw, "garden tool shed", district=district)
    if village:
        if rng.chance(0.45): city.prop("haystack.round", add(add(p0, mul(d, rng.uniform(4, pw-4))), mul(n, depth-4)), 0, "farmyard hay store", district=district)
        if rng.chance(0.3): city.prop(rng.pick(["tractor.open_utility", "tractor.cab_utility", "farm_trailer.flatbed"]), add(add(p0, mul(d, rng.uniform(3, pw-3))), mul(n, depth*0.45)), yaw+90, "farmyard machinery", district=district)
    elif rng.chance(0.25):
        city.prop(rng.pick(["car.boxy_sedan", "car.hatchback"]), add(add(p0, mul(d, rng.uniform(2.5, pw-2.5))), mul(n, 3.0)), yaw+90, "car parked in yard", district=district)
    if rng.chance(0.2): city.prop("laundry_line.posts", add(add(p0, mul(d, pw/2)), mul(n, depth*0.62)), yaw, "yard laundry line", district=district)

def _garage_edge(city, h, district, rng, a, d, n, w, L):
    s = 1.0
    while s < L-19:
        size = city.size("garage_row", rng, wmed=26.0, sigma=0.35, wmax=min(45.0, L-s-1))
        if size is None or size[0] < 19.2: break
        W0, D = size
        e = None; W = W0
        while W >= 19.2 and e is None:
            e = city.place("garage_row", add(add(a, mul(d, s+W/2)), mul(n, w/2)), d, W, D, SETBACK["garage"], district, street=h["street"], gap=0.4, rng=rng)
            if e is None: W = round(W-3.2, 2)
        s += (W+rng.uniform(4, 8)) if e else 2.0

def _shop_edge(city, h, district, rng, a, d, n, w, L):
    if L < 60 or not rng.chance(0.6): return
    W, D = city.size("shop_pavilion", rng, sigma=0.2)
    for s in (L*0.25, L*0.5, L*0.7):
        e = city.place("shop_pavilion", add(add(a, mul(d, s)), mul(n, w/2)), d, W, D, rng.uniform(4.5, 7.0), district, street=h["street"], gap=6.0, rng=rng)
        if e:
            city.prop("bus_stop.glazed_shelter", add(add(a, mul(d, s+W/2+5)), mul(n, w/2+1.6)), yaw_of(d)+180, "bus stop on microdistrict arterial", district=district)
            return

def _port_edge(city, h, face_poly, district, rng, a, d, n, w, L):
    quay = h["street"] == "Quay service road"
    s = 2.0
    while s < L-20:
        if quay:
            design = "transit_shed"; W, D = city.size(design, rng, wmed=64.0, sigma=0.15, wmax=L-s-2) or (0, 0); sb = SETBACK["port"]
        else:
            if rng.chance(0.35): s += rng.uniform(18, 32); continue  # open stockyard frontage
            design = "workshop_hall"; W, D = city.size(design, rng, wmed=38.0, sigma=0.2, wmax=L-s-2) or (0, 0); sb = rng.uniform(3.5, 6.0)
        if W <= 0: break
        lo = city.designs[design]["w"][0]; e = None
        for W in sorted({W, max(lo, round(W*0.85)), lo}, reverse=True):
            e = city.place(design, add(add(a, mul(d, s+W/2)), mul(n, w/2)), d, W, D, sb, district, street=h["street"], gap=3.0, face=face_poly, rng=rng)
            if e: break
        if e:
            if quay:  # siding between the shed and the quay road
                for k in range(int(W//24)):
                    p = add(add(a, mul(d, s+12+24*k+(W-24*int(W//24))/2)), mul(n, w/2+2.0))
                    city.prop("rail_siding.straight", p, yaw_of(d), "rail siding along transit shed apron", district=district)
                    if rng.chance(0.4): city.prop("freight_wagon.boxcar", p, yaw_of(d), "boxcar standing on shed siding", district=district, road_margin=0.6)
            s += W+rng.uniform(8, 14)
        else: s += 3.0

def clear_rect(city, poly, road_clear, seed_point=None):
    """Largest axis-aligned rect grown from the centroid that stays inside the
    block, road_clear from every road and clear of buildings/reservations."""
    c = seed_point or centroid(poly)
    def ok(r):
        p = [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]
        return all(in_poly(q, poly) for q in p) and city.road_gap(p) >= road_clear and not city.building_clash(p, 2.0) and not city.reserved(p, ("ravine",))
    r = [c[0]-1, c[1]-1, c[0]+1, c[1]+1]
    if not ok(r): return None
    for step in (4.0, 1.0, 0.25):
        grew = True
        while grew:
            grew = False
            for i, dv in ((0, -step), (1, -step), (2, step), (3, step)):
                t = list(r); t[i] += dv
                if ok(t): r = t; grew = True
    return r

def superblock(city, face, district):
    """Soviet microdistrict: slabs on the block axis in rows with >=16 u yards,
    a central school or kindergarten, shops on the arterial, garages at the edge."""
    poly = face["poly"]; A = abs(face["area"])
    b0 = bbox(poly); rng = Rng("superblock", round(b0[0]), round(b0[1]))
    R = clear_rect(city, poly, 6.0)
    if R is None: return
    rw, rh = R[2]-R[0], R[3]-R[1]
    civic = "school" if A > 10500 and rw > 50 and rh > 50 else ("kindergarten" if A > 6000 and rw > 40 else None)
    def place_civic():
        # After the slab rows: the school/kindergarten takes the largest leftover yard.
        if not civic: return
        for kind in dict.fromkeys([civic, "kindergarten"]):
            W, D = city.size(kind, rng, sigma=0.1)
            for gx in [0.5, 0.25, 0.75, 0.1, 0.9]:
                for gz in [0.5, 0.3, 0.7, 0.15, 0.85]:
                    for yaw in (0.0, 90.0):
                        cx = b0[0]+(b0[2]-b0[0])*gx; cz = b0[1]+(b0[3]-b0[1])*gz
                        if city.place(kind, None, None, W, D, 0, district, gap=6, face=poly, fixed=((cx, cz), yaw), rng=rng, road_clear=5):
                            if kind == "school":
                                for k in (-1, 1):
                                    city.prop("playground.frame", (cx+k*(W/2+8), cz) if yaw == 0 else (cx, cz+k*(W/2+8)), 0, "school playground")
                            return
    # Parallel slab rows along the block's long axis (local u), yards between rows
    # (local v). Real estates space 5-storey rows ~30-40 m apart: ~16-19 u here.
    along_x = (b0[2]-b0[0]) >= (b0[3]-b0[1])
    u0, u1 = (b0[0], b0[2]) if along_x else (b0[1], b0[3])
    v0, v1 = (b0[1], b0[3]) if along_x else (b0[0], b0[2])
    def at(u, v): return (u, v) if along_x else (v, u)
    v = v0+4; row = 0
    while v+9 <= v1-4:
        D = 10.5; u = u0+4; placed = False
        while u1-4-u >= 36:
            remaining = min(64.0, u1-4-u)
            design = "panel_9" if remaining >= 50 and rng.chance(0.4) else "panel_5"
            spec = city.designs[design]
            W = min(spec["w"][1], max(spec["w"][0], round(rng.uniform(*spec["w"])*2)/2), remaining)
            if W < spec["w"][0]: design, W = "panel_5", min(48.0, remaining)
            D2 = round(rng.uniform(*city.designs[design]["d"])*2)/2
            yaw = (0.0 if row % 2 == 0 else 180.0) if along_x else (90.0 if row % 2 == 0 else -90.0)
            e = city.place(design, None, None, W, D2, 0, district, gap=8.0, face=poly, fixed=(at(u+W/2, v+D2/2), yaw), rng=rng, road_clear=5.0)
            if e: u += W+rng.uniform(9, 13); placed = True; D = max(D, D2)
            else: u += 1.0
        v += (D+rng.uniform(16, 19)) if placed else 1.0
        row += 1 if placed else 0
    place_civic()
    # A perpendicular end slab closes the yards into an open court where room remains.
    for side in (0, 1):
        W, D2 = city.size("panel_5", rng, sigma=0.1)
        x = R[0]+D2/2 if side == 0 else R[2]-D2/2
        for dz in (0, -8, 8, -16, 16):
            if city.place("panel_5", None, None, W, D2, 0, district, gap=10.0, face=poly, fixed=((x, (R[1]+R[3])/2+dz), -90.0 if side == 0 else 90.0), rng=rng, road_clear=6.0):
                break

def yard_decor(city, poly, district, rng, kinds, step=9.0, density=0.35, context="yard", clearance=2.0):
    """Scatter decor over open ground inside poly on a jittered grid."""
    b = bbox(poly); count = 0
    z = b[1]+step/2
    while z < b[3]:
        x = b[0]+step/2
        while x < b[2]:
            if rng.chance(density):
                p = (x+rng.uniform(-step*0.3, step*0.3), z+rng.uniform(-step*0.3, step*0.3))
                if in_poly(p, poly):
                    kind, yaw = rng.pick(kinds), rng.pick([0.0, 90.0])
                    if city.prop(kind, p, yaw, context, district=district): count += 1
            x += step
        z += step
    return count

# --------------------------------------------------------------- compile
def compile_map(bp, draft=False):
    city = City(bp)
    sc = copy.deepcopy(bp["scenario"])
    sc.update(blocks=[], architecture=[], map_props=[], prop_blocks=[], water_blocks=[])
    sc["map_blueprint"] = "resources/maps/black_sea_harbor.json"
    sc["authorship"] = bp["proposal"]
    sc["footpaths"] = bp["footpaths"]
    streets, nodes, graph_edges, faces = build_graph(city)
    sc["roads"] = {"nodes": {}, "edges": []}
    for st in streets:
        for i, p in enumerate(st["pts"]): sc["roads"]["nodes"][f"{st['name']}:{i}"] = [round(p[0], 4), round(p[1], 4)]
        for i, (a, b) in enumerate(zip(st["pts"], st["pts"][1:])):
            sc["roads"]["edges"].append([f"{st['name']}:{i}", f"{st['name']}:{i+1}", st["w"], st["purpose"]])
            r = {"a": a, "b": b, "w": st["w"], "street": st["name"], "cls": st["cls"]}
            city.roads.append(r); city.road_grid.insert(grow(bbox([a, b]), st["w"]/2), r)
    # Reservations: objective poles and squares, force starts, woods, rough ground, rocks.
    for p in sc["objectives"]: city.circles.append((tuple(p), 14.0))
    for u in sc["player_force"]+sc["enemy_force"]:
        if u["kind"] not in ("drone", "helo", "boat"): city.circles.append((tuple(u["position"]), 8.0))
        elif u["kind"] == "helo": city.circles.append((tuple(u["position"]), 9.0))
    def reserve(poly, kind):
        item = {"polygon": [tuple(p) for p in poly], "kind": kind}; city.reserve_polys.append(item); city.rgrid.insert(bbox(item["polygon"]), item)
    for r in sc["woods"]: reserve(rect_poly([r[0]-2, r[1]-2, r[2]+4, r[3]+4]), "woods")
    reserve(rect_poly(sc["rubble"]), "rubble")
    for r in bp["rock_parcels"]: reserve(rect_poly([r[0]-2, r[1]-2, r[2]+4, r[3]+4]), "rock")
    # Deliberate landmarks first: they define squares, gates and skylines.
    for lm in bp["landmarks"]:
        W, D = lm["source_size"]
        e = city.place(lm["design"], None, None, W, D, 0, lm["district"], fixed=(tuple(lm["position"]), lm["rotation_degrees"]),
                       gap=0.5, floors=lm.get("floors"), variant=lm.get("variant", 0), rng=Rng("landmark", lm["design"], lm["position"]),
                       road_clear=lm.get("road_clear", 0.5), coast=1.0, extra={"landmark": True, **({"street": lm["street"]} if "street" in lm else {})})
        if e is None: raise ValueError(f"Landmark conflicts ({city.why}): {lm['design']} at {lm['position']}")
    for o in city.open_spaces:
        if o["kind"] in ("ravine",): continue  # allotments fill around the garages afterwards
        reserve(o["polygon"], o["kind"])
    # Blocks: bounded faces; outer faces only contribute open-sided frontage.
    faces.sort(key=lambda f: (round(centroid(f["poly"])[0], 2), round(centroid(f["poly"])[1], 2)))
    bounded = [f for f in faces if f["area"] > 1e-6]; outer = [f for f in faces if f["area"] <= 1e-6]
    for f in bounded:
        f["district"] = city.district_at(centroid(f["poly"]))
        f["morphology"] = city.morph.get(f["district"])
    for f in bounded:
        if f["morphology"] == "perimeter": corner_buildings(city, f, f["district"])
    for f in bounded:
        if f["morphology"] == "superblock": superblock(city, f, f["district"])
    # Quay frontage first (transit sheds own the apron), then main streets, then the rest.
    work = [(f, h) for f in bounded+outer for h in f["halfedges"]]
    rank = {"port": 0, "boulevard": 1, "avenue": 1, "arterial": 2, "garage": 2}
    work.sort(key=lambda fh: rank.get(fh[1]["cls"], 3))
    for f, h in work:
        face_poly = f["poly"] if f["area"] > 1e-6 else None
        if True:
            L = length(sub(h["b"], h["a"]))
            if L < 8: continue
            mid = add(add(h["a"], mul(sub(h["b"], h["a"]), 0.5)), mul(left(unit(sub(h["b"], h["a"]))), h["w"]/2+8))
            district = city.district_at(mid)
            morphology = city.morph.get(district)
            if face_poly is not None and f["morphology"] == "superblock" and morphology != "superblock": continue
            frontage(city, h, face_poly, morphology, district)
    # Close perimeter-block frontage gaps after every primary placement exists.
    for f in bounded:
        if f["morphology"] != "perimeter": continue
        for h in f["halfedges"]:
            mid = add(add(h["a"], mul(sub(h["b"], h["a"]), 0.5)), mul(left(unit(sub(h["b"], h["a"]))), h["w"]/2+8))
            if city.morph.get(city.district_at(mid)) == "perimeter": perimeter_fill(city, h, f["poly"], f["district"])
    for f in bounded:
        city.blocks_out.append({"district": f["district"], "morphology": f["morphology"],
                                "polygon": [[round(p[0], 3), round(p[1], 3)] for p in f["poly"]]})
    queued, city.queue = city.queue, None
    for args in queued: city.prop(*args)
    decorate(city, bp, bounded)
    apply_damage(city, sc, bp)
    enemy_defences(city, sc)
    # ------------------------------------------------------------- emit
    order = sorted(city.buildings, key=lambda e: (e["position"][1]//64, e["position"][0], e["position"][1]))
    for e in order:
        first = len(sc["blocks"]); sc["blocks"].extend(e["rects"])
        entry = {k: v for k, v in e.items() if k not in ("poly", "rects")}
        entry["collision"] = [first, len(e["rects"])]
        sc["architecture"].append(entry)
    sc["building_count"] = len(sc["architecture"])
    for r in bp["rock_parcels"]:
        first = len(sc["blocks"]); sc["blocks"].append(r)
        sc["architecture"].append({"design": "rock", "terrain_feature": "hill", "source_size": r[2:], "rotation_degrees": 0,
                                   "position": [r[0]+r[2]/2, r[1]+r[3]/2], "district": city.district_at((r[0]+r[2]/2, r[1]+r[3]/2)) or "open",
                                   "collision": [first, 1]})
    for item in city.props:
        out = {k: v for k, v in item.items() if k not in ("solid", "group")}
        sc["map_props"].append(out)
        if item["solid"]: sc["water_blocks" if item["domain"] == "sea" else "prop_blocks"].append(item["bounds"])
    sc["courtyards"] = city.courtyards
    sc["city_districts"] = [{"id": d["id"], "name": d["name"], "morphology": d["morphology"], "polygon": [list(p) for p in d["polygon"]]} for d in city.districts]
    sc["open_spaces"] = [{"name": o["name"], "kind": o["kind"], "polygon": [list(p) for p in o["polygon"]]} for o in city.open_spaces]
    sc["urban_blocks"] = city.blocks_out
    sc["layout_validation"] = dict(bp["layout_validation"])
    sc["layout_validation"]["damage_hotspots"] = [list(p) for p in sc["objectives"]]+bp["damage_front"]
    sc["layout_validation"]["primary_streets"] = [st["name"] for st in bp["streets"] if st.get("width", 0) >= 16]
    if not draft and not 450 <= sc["building_count"] <= 700: raise ValueError(f"{sc['building_count']} buildings outside 450-700")
    if not draft and len(sc["map_props"]) < 1500: raise ValueError(f"Only {len(sc['map_props'])} decor placements")
    return sc

# ------------------------------------------------------------------ decor
def decorate(city, bp, bounded):
    # Street furniture by street class.
    for st in city.bp["streets"]:
        cls = st.get("class", "street"); w = st["width"]; pts = st["points"]
        rng = Rng("street-decor", st["name"])
        for a, b in zip(pts, pts[1:]):
            d = unit(sub(b, a)); L = length(sub(b, a)); n = left(d)
            if cls in ("boulevard", "avenue"):
                step = 9.0 if cls == "boulevard" else 11.0
                for k in range(1, int(L//step)):
                    for side in (1, -1):
                        p = add(add(a, mul(d, k*step)), mul(n, side*(w/2+1.6)))
                        if k % 3 == 1: city.prop("lamp.boulevard_double", p, 0, f"{cls} lighting", road_margin=0.6)
                        else: city.prop("tree.plane_street", p, 0, f"plane tree on {cls}", road_margin=0.6)
                    if cls == "boulevard" and k % 4 == 2:
                        city.prop("bench.park", add(add(a, mul(d, k*step+3)), mul(n, -(w/2+2.6))), yaw_of(d)+180, "boulevard bench")
            elif cls == "arterial":
                for k in range(1, int(L//30)+1):
                    city.prop("trolley_pole.span", add(add(a, mul(d, k*30-15)), mul(n, w/2+0.9)), 0, "trolleybus overhead span pole", road_margin=0.6)
    # Squares, parks and other deliberate open spaces.
    for o in city.open_spaces:
        poly = o["polygon"]; rng = Rng("open", o["name"]); kind = o["kind"]; dist = city.district_at(centroid(poly))
        if kind == "square":
            yard_decor(city, poly, dist, rng, ["flowerbed.round", "bench.park", "lamp.boulevard_double"], step=10, density=0.45, context="paved square furniture")
            for k, kind2 in enumerate(["kiosk.newspaper", "tree.plane_street", "tree.plane_street"]):
                c = poly[k % len(poly)]; cc = centroid(poly); p = add(c, mul(sub(cc, c), 0.18))
                city.prop(kind2, p, 0, "square edge")
        elif kind in ("park", "hill_park", "seafront"):
            yard_decor(city, poly, dist, rng, ["tree.crimean_pine", "tree.plane_street", "tree.acacia", "bench.park", "tree.crimean_pine"], step=8, density=0.55, context="public garden planting")
        elif kind == "cathedral_close":
            yard_decor(city, poly, dist, rng, ["tree.cypress"], step=6, density=0.6, context="cypresses in cathedral close")
        elif kind == "cemetery":
            b = bbox(poly); z = b[1]+4
            while z < b[3]-3:
                x = b[0]+4
                while x < b[2]-3:
                    if in_poly((x, z), poly): city.prop("tree.cypress" if (int(x)+int(z)) % 3 == 0 else "grass_patch.short_sward", (x, z), 0, "cemetery rows and cypresses")
                    x += 7
                z += 8
            for a, b2 in edges(poly): city.prop_line("wall.stone_yard", a, b2, "cemetery wall", "cemetery", inset=2)
        elif kind == "vineyard":
            b = bbox(poly); z = b[1]+3
            while z < b[3]-2:
                x = b[0]+11
                while x < b[2]-10:
                    if in_poly((x-10, z), poly) and in_poly((x+10, z), poly): city.prop("vineyard.trellis_row", (x, z), 0, "vineyard trellis row", group="vine")
                    x += 22
                z += 4.5
            for x in range(int(b[0])+3, int(b[2])-2, 7):  # poplar windbreak along the north edge
                p = (x, b[1]-1.5)
                if in_poly((x, b[1]+2), poly): city.prop("tree.poplar", p, 0, "poplar windbreak on field edge")
        elif kind == "field":
            yard_decor(city, poly, dist, rng, ["haystack.round", "grass_patch.dry_tussocks"], step=12, density=0.4, context="harvested field")
        elif kind == "tank_farm":
            b = bbox(poly)
            for x in range(int(b[0])+8, int(b[2])-6, 16):
                for z in range(int(b[1])+8, int(b[3])-6, 16):
                    city.prop("tank.fuel_storage", (x, z), 0, "fuel tank farm")
            for a, b2 in edges(poly): city.prop_line("fence.concrete_panel", a, b2, "tank farm perimeter fence", "tankfence", inset=1)
        elif kind == "stockyard":
            b = bbox(poly)
            for z in range(int(b[1])+4, int(b[3])-3, 6):
                for x in range(int(b[0])+5, int(b[2])-4, 8):
                    if rng.chance(0.7): city.prop("container.stack" if rng.chance(0.75) else "pipe_stack.pyramid", (x, z), 0, "container and pipe stockyard")
        elif kind == "parade":
            for a, b2 in edges(poly):
                for t in (0.2, 0.8): city.prop("lamp.boulevard_double", add(a, mul(sub(b2, a), t)), 0, "parade ground lighting")
        elif kind == "headland":
            yard_decor(city, poly, dist, rng, ["tree.crimean_pine", "tree.crimean_pine", "grass_patch.dry_tussocks", "broken_tree.snapped_snag"], step=13, density=0.45, context="pine scrub on headland")
        elif kind == "scrub":
            yard_decor(city, poly, dist, rng, ["grass_patch.dry_tussocks", "hedgerow.mixed_shrubs", "tree.acacia"], step=10, density=0.4, context="quarry scrub at town edge")
        elif kind == "ravine":
            yard_decor(city, poly, dist, rng, ["greenhouse.film", "shed.small", "tree.acacia", "grass_patch.short_sward"], step=7, density=0.55, context="ravine allotments")
        elif kind == "sports":
            for a, b2 in edges(poly): city.prop_line("fence.chainlink", a, b2, "school sports ground fence", "sport")
    # Crane rails along the quay edge, cranes over the apron.
    for rail in bp["crane_rails"]:
        pts = rail["points"]
        for a, b in zip(pts, pts[1:]):
            d = unit(sub(b, a)); L = length(sub(b, a))
            for k in range(int(L//24)):
                city.prop("rail_siding.straight", add(a, mul(d, 12+24*k)), yaw_of(d), "crane rail along quay edge")
            for k in range(int(L//rail["spacing"])):
                city.prop("portal_crane.rail", add(a, mul(d, rail["spacing"]*(k+0.5))), yaw_of(d), "portal crane on quay rail", road_margin=0.2)
    # Courtyards of perimeter blocks: trees, sheds, laundry, parked cars.
    for f in bounded:
        rng = Rng("court", round(centroid(f["poly"])[0], 1), round(centroid(f["poly"])[1], 1))
        if f["morphology"] == "perimeter":
            court = interior_rect(city, f["poly"])
            civic = ("square", "cathedral_close", "hill_park", "seafront")
            # Squares and parks inside a block are public space, not a residential back yard.
            if court and any(o["kind"] in civic and polys_touch(o["polygon"], rect_poly(court)) for o in city.open_spaces):court = None
            if court:
                city.courtyards.append([round(v, 3) for v in court])
                cp = rect_poly(court)
                yard_decor(city, cp, f["district"], rng, ["tree.plane_street", "shed.small", "laundry_line.posts", "car.boxy_sedan", "bench.park", "tree.acacia", "dumpster.row"], step=8, density=0.5, context="courtyard of perimeter block")
        elif f["morphology"] == "superblock":
            yard_decor(city, f["poly"], f["district"], rng, ["playground.frame", "parking.bay", "dumpster.row", "laundry_line.posts", "tree.acacia", "tree.acacia", "bench.park", "heat_pipe.overground", "car.boxy_sedan", "car.hatchback"], step=11, density=0.5, context="microdistrict yard")
        elif f["morphology"] == "port":
            yard_decor(city, f["poly"], f["district"], rng, ["container.stack", "pipe_stack.paired_large", "pipe_stack.pyramid", "pickup.crew_cab_canopy", "gantry.fixed"], step=13, density=0.3, context="port yard stock and service equipment")
        elif f["morphology"] in ("private", "north", "village", "garages"):
            yard_decor(city, f["poly"], f["district"], rng, ["tree.acacia", "orchard.open_crown", "grass_patch.short_sward"], step=12, density=0.25, context="block-interior gardens")
    # Port perimeter fence along the ring road frontage, gates left at roads.
    for a, b in bp["port_fence"]: city.prop_line("fence.concrete_panel", tuple(a), tuple(b), "port perimeter concrete fence", "portfence")
    for a, b in bp["compound_fence"]: city.prop_line("fence.concrete_panel", tuple(a), tuple(b), "barracks compound fence", "compoundfence")
    for item in bp["decor"]:
        city.prop(item["id"], tuple(item["position"]), item.get("rotation_degrees", 0), item["context"], domain=item.get("domain", "land"), road_margin=item.get("road_margin", 0.5))
    # Legacy waterfront: quay walls, bollards and moored boats.
    for a, b in bp["quay_walls"]:
        delta = sub(b, a); span = length(delta); v = mul(delta, 1/span); normal = (-v[1], v[0]); yaw = math.degrees(math.atan2(v[0], v[1]))
        for j in range(1, int(span/16)):
            p = add(add(a, mul(v, j*16)), mul(normal, 1.4))
            city.prop("quay_bay.existing", p, yaw, "land-backed quay wall facing actual harbor polygon", road_margin=0)
            city.prop("mooring_rope.bollard", add(p, mul(normal, 2.8)), yaw, "quay mooring point on land behind wall")
            if j % 2 == 0: city.prop("mooring_rope.coil", add(p, mul(normal, 4.6)), yaw, "flush rope storage beside mooring bollard")

def interior_rect(city, poly):
    """Largest open axis-aligned rect grown from the block centroid."""
    c = centroid(poly)
    if not in_poly(c, poly): return None
    r = [c[0]-1, c[1]-1, c[0]+1, c[1]+1]
    def ok(r):
        p = [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]
        if not all(in_poly(q, poly) for q in p): return False
        if city.road_gap(p) < 1.0 or city.building_clash(p, 1.2): return False
        return True
    if not ok(r): return None
    for _ in range(60):
        grew = False
        for i, dv in ((0, -1), (1, -1), (2, 1), (3, 1)):
            t = list(r); t[i] += dv
            if ok(t): r = t; grew = True
        if not grew: break
    w, h = r[2]-r[0], r[3]-r[1]
    return [r[0], r[1], w, h] if w*h >= 80 else None

# ------------------------------------------------------------ enemy defences
def enemy_defences(city, sc):
    """Prepared enemy positions per objective, facing the player's land approach:
    wire belt, trench pair, MG bunker, AT gun near a road, hedgehogs across the
    approach road, and (for the inner objectives) a command post and ammo depot.
    Every work is placed on clear land outside buildings, roads, water and the
    objective capture circle; hedgehogs alone may sit on roads."""
    defs = json.loads((ROOT/"resources/field_units.json").read_text())
    works, rects = [], []
    entry = tuple(sc["field_insertion"])
    def fits(kind, p, rotated, on_road=False):
        w, d = defs[kind]["footprint"]
        if rotated: w, d = d, w
        r = [p[0]-w/2, p[1]-d/2, w, d]; poly = rect_poly(r)
        if not city.land_ok(poly, 1.0) or city.building_clash(poly, 1.0) or city.prop_clash(r, 1.5): return None
        gap = city.road_gap(poly)
        if on_road and gap > -1.5: return None
        if not on_road and gap < 0.6: return None
        if any(length(sub(p, tuple(o))) < 16.5 for o in sc["objectives"]): return None
        if any(overlap_rect(r, o, 0.8) for o in rects): return None
        return r
    def place(kind, p, rotated, on_road=False, reach=18.0):
        for radius in [0.0]+[1.5*k for k in range(1, int(reach/1.5)+1)]:
            for i in range(1 if radius == 0 else 16):
                q = add(p, mul((math.cos(i*math.pi/8), math.sin(i*math.pi/8)), radius))
                r = fits(kind, q, rotated, on_road)
                if r:
                    rects.append(r); works.append({"kind": kind, "position": [round(q[0], 3), round(q[1], 3)], "rotated": rotated})
                    return True
        return False
    for index, o in enumerate(sc["objectives"]):
        o = tuple(o); f = unit(sub(entry, o)); l = left(f)
        across = abs(l[0]) < abs(l[1])  # long axis of linear works runs along l
        place("bunker", add(o, mul(f, 20)), False)
        for side in (-1, 1): place("fighting_trench", add(add(o, mul(f, 24)), mul(l, side*9)), across)
        for k in (-1, 0, 1): place("concertina_wire", add(add(o, mul(f, 32)), mul(l, k*8)), across)
        gun_side = min((-1, 1), key=lambda s: min(length(sub(add(o, mul(l, s*12)), r["a"])) for r in city.roads))
        place("at_gun", add(add(o, mul(f, 18)), mul(l, gun_side*12)), False)
        # Hedgehogs across the approach road nearest the wire belt.
        best = None
        for r in city.roads:
            for t in (0.2, 0.4, 0.6, 0.8):
                q = add(r["a"], mul(sub(r["b"], r["a"]), t)); dist = length(sub(q, add(o, mul(f, 30))))
                if dot(sub(q, o), f) > 18 and dist < 22 and (best is None or dist < best[0]): best = (dist, q, r)
        if best:
            d = unit(sub(best[2]["b"], best[2]["a"]))
            place("tank_obstacles", best[1], abs(d[0]) > abs(d[1]), on_road=True, reach=4.5)
        if index > 0:
            place("command_post", add(add(o, mul(f, -20)), mul(l, 8)), False)
            place("ammo_depot", add(add(o, mul(f, -22)), mul(l, -9)), False)
    sc["enemy_works"] = works
    # Garrison and reserve: defenders hold behind their works; armour reserve waits at the staging area.
    trenches = [w["position"] for w in works if w["kind"] == "fighting_trench"]
    for index, o in enumerate(sc["objectives"]):
        f = unit(sub(entry, tuple(o)))
        # Riflemen man the nearest trenches of their own position; the AT team stays behind them.
        def roomy(p):  # a 3-soldier section (radius 2.65) must stand clear of buildings and solid props
            r = [p[0]-3.0, p[1]-3.0, 6.0, 6.0]
            return city.land_ok(rect_poly(r), 0.5) and not city.building_clash(rect_poly(r), 0.2) and not city.prop_clash(r, 0.2)
        own = [p for p in sorted(trenches, key=lambda p: length(sub(tuple(p), tuple(o)))) if roomy(p)][:2]
        for k, kind in enumerate(("rifle", "rifle")):
            p = own[k] if k < len(own) and length(sub(tuple(own[k]), tuple(o))) < 40 else [o[0]+f[0]*12+left(f)[0]*(5 if k else -5), o[1]+f[1]*12+left(f)[1]*(5 if k else -5)]
            sc["enemy_force"].append({"kind": kind, "position": [round(p[0], 2), round(p[1], 2)]})
        sc["enemy_force"].append({"kind": "atgm", "position": [round(o[0]+f[0]*10, 2), round(o[1]+f[1]*10, 2)]})
    sc["reserve_force"] = [{"kind": k, "position": list(sc["field_enemy_insertion"])} for k in ("tank", "tank", "rifle", "rifle", "rifle", "atgm", "aa")]
    # Test-tuned pressure: the player digs in first (more starting supply), then
    # escalating enemy waves arrive from the NE staging area until its logistics fall.
    sc["field_supply"] = 1600
    sc["field_income"] = 3.0
    sc["enemy_waves"] = {"first": 90, "interval": 95, "max_wave": 10}
    # Extra defenders: a second rifle team and a tank per objective.
    for o in sc["objectives"]:
        f = unit(sub(entry, tuple(o)))
        for kind, back, side in (("rifle", 4, -9), ("tank", -6, 0)):
            sc["enemy_force"].append({"kind": kind, "position": [round(o[0]+f[0]*back+left(f)[0]*side, 2), round(o[1]+f[1]*back+left(f)[1]*side, 2)]})

def overlap_rect(a, b, pad=0.0):
    return a[0]-pad < b[0]+b[2] and b[0]-pad < a[0]+a[2] and a[1]-pad < b[1]+b[3] and b[1]-pad < a[1]+a[3]

def apply_damage(city, sc, bp):
    """Clustered damage: 10-20% within ~60 u of objectives and the freight
    front, falling to zero beyond ~75 u. Deterministic per building seed."""
    hot = [tuple(p) for p in sc["objectives"]]+[tuple(p) for p in bp["damage_front"]]
    near = []
    for e in city.buildings:
        c = e["position"]; dmin = min(length(sub(c, h)) for h in hot)
        if dmin < 60: near.append(e); continue
        # Fading fringe beyond the fighting core.
        r = Rng("damage", e["seed"])
        if dmin < 75 and r.chance(0.15*(75-dmin)/15): e["damage"] = 1
    # Fixed 15% quota inside the core: small samples cannot drift outside 10-20%.
    near.sort(key=lambda e: Rng("damage", e["seed"]).next())
    for e in near[:round(len(near)*0.15)]:
        r = Rng("damage-level", e["seed"])
        e["damage"] = 2 if (r.chance(0.3) and not e.get("landmark")) else 1

def main():
    args = argparse.ArgumentParser(description=__doc__); args.add_argument("--check", action="store_true"); args.add_argument("--draft", action="store_true", help="skip count limits while authoring"); args = args.parse_args()
    bp = json.loads(BLUEPRINT.read_text()); scenario = compile_map(bp, args.draft)
    old = json.loads(SCENARIOS.read_text()); output = copy.deepcopy(old[:6])
    for item in output: item["hidden"] = True
    output.append(scenario); text = json.dumps(output, indent=2)+"\n"
    if args.check:
        if SCENARIOS.read_text() != text: raise SystemExit("Harbor generated data is stale; run tools/build_harbor_map.py")
        print("HARBOR COMPILER CHECK: reproducible")
    else: SCENARIOS.write_text(text)
    counts = {}
    for e in scenario["architecture"]: counts[e["design"]] = counts.get(e["design"], 0)+1
    print(f"HARBOR: {scenario['building_count']} buildings, {len(scenario['blocks'])} collision rects, {len(scenario['map_props'])} decor placements, {len(scenario['roads']['edges'])} road segments")
    print("  designs: "+", ".join(f"{k}={v}" for k, v in sorted(counts.items())))

if __name__ == "__main__": main()
