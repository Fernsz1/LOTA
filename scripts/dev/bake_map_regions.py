#!/usr/bin/env python3
"""Bake Philippines region GeoJSON into data/map_regions.json for LOTA map select.

Groups 17 PSGC admin regions into 5 game regions, dissolves internal province
borders (directed-edge cancellation), drops speck islands, and equirectangular-
projects into a top-left-origin pixel space (height fit to TARGET_H). Runtime
loads the baked JSON only; it never parses GeoJSON.

Run: python3 scripts/dev/bake_map_regions.py
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "data", "geojson_src")
OUT = os.path.join(ROOT, "data", "map_regions.json")

TARGET_H = 560.0        # projected map height in px; width follows aspect
MIN_AREA_PX = 8.0       # drop rings whose projected area is below this (specks)
RND = 6                 # coordinate rounding (decimal places) for edge matching

# game region -> metadata + source file codes
GROUPS = [
    {"id": 1, "name": "Luzon", "codes": ["400000000", "1700000000", "500000000"],
     "stage": "Bahay Kubo Training Yard", "fighter": "Arnis Fighter", "accent": "#f5b431",
     "slug": "bahay_kubo",
     "ctx": "In a quiet village in Luzon, warriors train in secret, preserving the way of the rattan."},
    {"id": 2, "name": "Northern Luzon", "codes": ["100000000", "200000000", "1400000000"],
     "stage": "Mountain Festival Grounds", "fighter": "Buno Fighter", "accent": "#22d3ee",
     "slug": "mountain_festival",
     "ctx": "In the highlands, strength is tested in fair combat. Buno is respect, balance, and honor."},
    {"id": 3, "name": "Metro Manila", "codes": ["300000000", "1300000000"],
     "stage": "Barangay Boxing Ring", "fighter": "Dirty Boxing Fighter", "accent": "#ef4444",
     "slug": "barangay_ring",
     "ctx": "From makeshift rings in the barangays rise champions. Grit, heart, and never giving up."},
    {"id": 4, "name": "Visayas", "codes": ["600000000", "700000000", "800000000"],
     "stage": "Heritage Plaza", "fighter": "Sikaran Fighter", "accent": "#b366ff",
     "slug": "heritage_plaza",
     "ctx": "Sikaran was born from freedom and resilience. Warriors honed their kicks to protect their people."},
    {"id": 5, "name": "Mindanao",
     "codes": ["900000000", "1000000000", "1100000000", "1200000000", "1600000000", "1900000000"],
     "stage": "Beach Court at Dusk", "fighter": "Sepak Takraw Striker", "accent": "#fb7a2d",
     "slug": "beach_court",
     "ctx": "On coastal shores, every kick honors the players who made the Philippines a Sepak Takraw powerhouse."},
]


def _rings_from_geometry(geom):
    """Yield every linear ring (list of [lon,lat]) from a Polygon/MultiPolygon."""
    t = geom["type"]
    if t == "Polygon":
        for ring in geom["coordinates"]:
            yield ring
    elif t == "MultiPolygon":
        for poly in geom["coordinates"]:
            for ring in poly:
                yield ring


def _load_group_rings(codes):
    rings = []
    for code in codes:
        path = os.path.join(SRC, "provdists-region-%s.0.001.json" % code)
        with open(path) as f:
            gj = json.load(f)
        for feat in gj["features"]:
            geom = feat.get("geometry")
            if geom:
                rings.extend(_rings_from_geometry(geom))
    return rings


def _key(pt):
    return (round(pt[0], RND), round(pt[1], RND))


def _dissolve(rings):
    """Directed-edge cancellation -> list of boundary rings (lon/lat)."""
    edges = set()          # (keyA, keyB)
    coord = {}             # key -> original [lon,lat]
    for ring in rings:
        for i in range(len(ring) - 1):
            a, b = ring[i], ring[i + 1]
            ka, kb = _key(a), _key(b)
            if ka == kb:
                continue
            coord[ka], coord[kb] = a, b
            edges.add((ka, kb))
    # cancel any edge whose reverse also exists (shared internal border)
    survivors = {(a, b) for (a, b) in edges if (b, a) not in edges}
    # stitch survivors into closed rings
    adj = {}
    for (a, b) in survivors:
        adj.setdefault(a, []).append(b)
    out_rings = []
    remaining = set(survivors)
    while remaining:
        start, nxt = next(iter(remaining))
        ring_keys = [start]
        ring = [coord[start]]
        cur, prev_edge = nxt, (start, nxt)
        remaining.discard(prev_edge)
        guard = 0
        while cur != start and guard < 100000:
            if cur in ring_keys:
                # `cur` has out-degree > 1: two survivor loops touch at this
                # single vertex (e.g. two islands/provinces meeting at a
                # point). Split off everything traced since the earlier
                # visit to `cur` as its own closed, simple ring, then keep
                # tracing the outer ring from the truncated prefix so no
                # ring revisits a non-closing vertex.
                split_idx = ring_keys.index(cur)
                sub_ring = ring[split_idx:] + [coord[cur]]
                out_rings.append(sub_ring)
                ring_keys = ring_keys[:split_idx + 1]
                ring = ring[:split_idx + 1]
            else:
                ring_keys.append(cur)
                ring.append(coord[cur])
            outs = [b for b in adj.get(cur, []) if (cur, b) in remaining]
            if not outs:
                break
            nb = outs[0]
            remaining.discard((cur, nb))
            cur = nb
            guard += 1
        ring.append(coord[start])
        out_rings.append(ring)
    return out_rings


def _shoelace(ring):
    s = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i]
        x1, y1 = ring[i + 1]
        s += x0 * y1 - x1 * y0
    return s * 0.5


def _centroid(ring):
    a = _shoelace(ring)
    if abs(a) < 1e-12:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        return [sum(xs) / len(xs), sum(ys) / len(ys)]
    cx = cy = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i]
        x1, y1 = ring[i + 1]
        cross = x0 * y1 - x1 * y0
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    cx /= (6 * a)
    cy /= (6 * a)
    return [cx, cy]


def main():
    groups_rings = {}
    for g in GROUPS:
        groups_rings[g["id"]] = _dissolve(_load_group_rings(g["codes"]))

    # global bbox for the shared projection
    all_pts = [pt for rings in groups_rings.values() for r in rings for pt in r]
    lon_min = min(p[0] for p in all_pts)
    lon_max = max(p[0] for p in all_pts)
    lat_min = min(p[1] for p in all_pts)
    lat_max = max(p[1] for p in all_pts)
    mid_lat = math.radians((lat_min + lat_max) / 2.0)
    raw_w = (lon_max - lon_min) * math.cos(mid_lat)
    raw_h = (lat_max - lat_min)
    k = TARGET_H / raw_h
    map_w = raw_w * k
    map_h = raw_h * k

    def project(pt):
        x = (pt[0] - lon_min) * math.cos(mid_lat) * k
        y = (lat_max - pt[1]) * k
        return (x, y)

    regions = []
    for g in GROUPS:
        proj_rings = []
        for r in groups_rings[g["id"]]:
            pr = [project(pt) for pt in r]
            if abs(_shoelace(pr)) < MIN_AREA_PX:
                continue          # speck island
            proj_rings.append(pr)
        proj_rings.sort(key=lambda r: abs(_shoelace(r)), reverse=True)
        anchor = _centroid(proj_rings[0])
        flat = [[c for pt in r for c in (round(pt[0], 2), round(pt[1], 2))] for r in proj_rings]
        regions.append({
            "id": g["id"],
            "display_name": g["name"],
            "region_number": g["id"],
            "stage_name": g["stage"],
            "fighter_name": g["fighter"],
            "story_context": g["ctx"],
            "accent_color": g["accent"],
            "stage_data_path": "res://stages/%s/%s_data.tres" % (g["slug"], g["slug"]),
            "label_anchor": [round(anchor[0], 2), round(anchor[1], 2)],
            "outline_polygons": flat,
        })

    out = {"map_size": [round(map_w, 2), round(map_h, 2)], "regions": regions}
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1)

    # self-check
    assert len(regions) == 5, "expected 5 regions"
    for r in regions:
        assert r["outline_polygons"] and all(len(p) >= 6 for p in r["outline_polygons"]), \
            "region %s has an empty ring" % r["id"]
    print("baked %d regions, map_size=%s -> %s" % (len(regions), out["map_size"], OUT))


if __name__ == "__main__":
    main()
