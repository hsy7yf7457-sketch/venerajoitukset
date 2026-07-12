#!/usr/bin/env python3
"""Append concentric TEST restriction rings around a point for on-device testing.

Idempotent: removes any previously added test areas (id >= TEST_ID_BASE) before
re-adding, so you can run it repeatedly. Run `refresh_data.py` to get back to a
clean official dataset.

    python3 Scripts/add_test_polygons.py            # uses the default location
    python3 Scripts/add_test_polygons.py 60.4260 21.8070
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "App", "Resources", "restrictions.json")

TEST_ID_BASE = 9_000_000
DEFAULT_LAT = 60.425952
DEFAULT_LON = 21.807002

# (inner_radius_m, outer_radius_m, codes, speed) — a gap band is simply omitted.
RINGS = [
    (0,  10, ["speedLimit"],                 10),   # solid disc
    # 10-20 m: intentionally left empty -> "no limit"
    (20, 30, ["speedLimit", "wakeBan"],      20),
    (30, 40, ["speedLimit", "anchoringBan"], 30),
]

SEGMENTS = 72


def ring(lat, lon, radius_m, segments=SEGMENTS):
    """A closed circle of `radius_m` around (lat, lon) as [ [lon,lat], ... ]."""
    if radius_m <= 0:
        return []
    dlat = radius_m / 111_320.0
    dlon = radius_m / (111_320.0 * math.cos(math.radians(lat)))
    pts = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        pts.append([round(lon + dlon * math.cos(a), 7),
                    round(lat + dlat * math.sin(a), 7)])
    pts.append(pts[0])  # close the ring
    return pts


def bbox_of(rings):
    xs = [p[0] for r in rings for p in r]
    ys = [p[1] for r in rings for p in r]
    return [min(xs), min(ys), max(xs), max(ys)]


def main():
    lat = float(sys.argv[1]) if len(sys.argv) > 2 else DEFAULT_LAT
    lon = float(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_LON

    with open(DATA, encoding="utf-8") as fh:
        snapshot = json.load(fh)

    areas = [a for a in snapshot["areas"] if (a.get("id") or 0) < TEST_ID_BASE]
    removed = len(snapshot["areas"]) - len(areas)

    for idx, (r_in, r_out, codes, speed) in enumerate(RINGS):
        outer = ring(lat, lon, r_out)
        polygon = [outer]
        if r_in > 0:
            polygon.append(ring(lat, lon, r_in))  # hole -> annulus
        label = "+".join(codes)
        areas.append({
            "id": TEST_ID_BASE + idx + 1,
            "codes": codes,
            "speed": speed,
            "name": f"TEST ring {r_in}-{r_out} m ({label})",
            "exception": None,
            "info": "Synthetic test zone (not real).",
            "validFrom": "2000-01-01Z",
            "validTo": None,
            "bbox": bbox_of(polygon),
            "polygons": [polygon],
        })

    snapshot["areas"] = areas
    snapshot["count"] = len(areas)

    with open(DATA, "w", encoding="utf-8") as fh:
        json.dump(snapshot, fh, ensure_ascii=False, separators=(",", ":"))

    print(f"Center: lat {lat}, lon {lon}")
    print(f"Removed {removed} old test area(s); added {len(RINGS)} ring(s).")
    print(f"Total areas now: {len(areas)}")


if __name__ == "__main__":
    main()
