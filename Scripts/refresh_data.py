#!/usr/bin/env python3
"""Build the bundled marine-restriction snapshot for the iOS app.

Source: Finnish Transport Infrastructure Agency (Väylävirasto) open data,
        OGC API Features, layer `vesivaylatiedot:rajoitusalue_a_uusi`.
        Licence: CC BY 4.0. Data returned in WGS84 (lon/lat).

Run this at most ~monthly (the source updates weekly but limits rarely change).
It overwrites App/Resources/restrictions.json and stamps the build date.

    python3 Scripts/refresh_data.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

BASE = "https://avoinapi.vaylapilvi.fi/vaylatiedot/ogc/features/v1"
COLLECTION = "vesivaylatiedot:rajoitusalue_a_uusi"
URL = f"{BASE}/collections/{COLLECTION}/items?limit=5000&f=json"

# Restriction type codes (RAJOITUSTYYPIT) -> stable machine key used by the app.
CODE_KEYS = {
    "01": "speedLimit",
    "02": "wakeBan",
    "03": "windsurfBan",
    "04": "jetSkiBan",
    "05": "motorBan",
    "06": "anchoringBan",
    "07": "mooringBan",
    "08": "berthingBan",
    "09": "overtakingBan",
    "10": "meetingBan",
    "11": "speedRecommendation",
    "12": "waterSkiBan",
    "13": "powerLimit",
}

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(HERE, "..", "App", "Resources", "restrictions.json")


def round_ring(ring, ndigits=6):
    return [[round(x, ndigits), round(y, ndigits)] for x, y in ring]


def normalize_geometry(geom):
    """Return list of polygons; each polygon is a list of rings (lon/lat)."""
    t = geom["type"]
    coords = geom["coordinates"]
    if t == "Polygon":
        return [[round_ring(r) for r in coords]]
    if t == "MultiPolygon":
        return [[round_ring(r) for r in poly] for poly in coords]
    raise ValueError(f"unexpected geometry type {t}")


def bbox_of(polygons):
    xs, ys = [], []
    for poly in polygons:
        for x, y in poly[0]:  # outer ring is enough for bbox
            xs.append(x)
            ys.append(y)
    return [min(xs), min(ys), max(xs), max(ys)]


def parse_codes(raw):
    if not raw:
        return []
    keys = []
    for part in raw.split(","):
        part = part.strip()
        key = CODE_KEYS.get(part)
        if key:
            keys.append(key)
    return keys


def main():
    print(f"Fetching {URL}")
    with urllib.request.urlopen(URL, timeout=120) as resp:
        data = json.load(resp)

    feats = data.get("features", [])
    matched = data.get("numberMatched")
    print(f"Downloaded {len(feats)} features (numberMatched={matched}).")
    if matched and len(feats) < matched:
        print("WARNING: not all features returned; raise the limit.", file=sys.stderr)

    out_areas = []
    skipped = 0
    for f in feats:
        props = f.get("properties", {})
        geom = f.get("geometry")
        codes = parse_codes(props.get("rajoitustyypit"))
        if not geom or not codes:
            skipped += 1
            continue
        polygons = normalize_geometry(geom)
        suuruus = props.get("suuruus")
        speed = None
        if "speedLimit" in codes:
            try:
                speed = int(suuruus)
            except (TypeError, ValueError):
                speed = None
        out_areas.append({
            "id": props.get("id"),
            "codes": codes,
            "speed": speed,
            "name": props.get("nimisijainti"),
            "exception": (props.get("poikkeus") or "").strip() or None,
            "info": (props.get("lisatieto") or "").strip() or None,
            "validFrom": props.get("alkupaivamaara"),
            "validTo": props.get("loppupaivamaara"),
            "bbox": bbox_of(polygons),
            "polygons": polygons,
        })

    snapshot = {
        "source": COLLECTION,
        "attribution": "© Väylävirasto (Finnish Transport Infrastructure Agency), CC BY 4.0",
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "crs": "EPSG:4326",
        "count": len(out_areas),
        "areas": out_areas,
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(snapshot, fh, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(OUT_PATH)
    print(f"Wrote {len(out_areas)} areas ({skipped} skipped) -> {os.path.relpath(OUT_PATH)}")
    print(f"Snapshot size: {size/1024:.0f} KB, generatedAt={snapshot['generatedAt']}")


if __name__ == "__main__":
    main()
