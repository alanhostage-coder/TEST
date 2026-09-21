#!/usr/bin/env python3
"""Build a compact, source-dated PUA location patch from OpenStreetMap.

The output contains OSM geometry and names. Values that are not explicitly
surveyed in OSM are labelled as estimates instead of being presented as facts.
"""

from __future__ import annotations

import argparse
import json
import math
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_POSTCODE = "EH15 2BZ"
DEFAULT_LAT = 55.951507
DEFAULT_LON = -3.107122


def local_point(lat: float, lon: float, centre_lat: float, centre_lon: float) -> list[float]:
    metres_per_lon = 111_320.0 * math.cos(math.radians(centre_lat))
    return [round((lon - centre_lon) * metres_per_lon, 3), round(-(lat - centre_lat) * 111_320.0, 3)]


def geometry_points(geometry: list[dict], centre_lat: float, centre_lon: float, min_gap: float = 0.75) -> list[list[float]]:
    points: list[list[float]] = []
    for item in geometry:
        point = local_point(float(item["lat"]), float(item["lon"]), centre_lat, centre_lon)
        if not points or math.dist(points[-1], point) >= min_gap:
            points.append(point)
    if geometry:
        tail = local_point(float(geometry[-1]["lat"]), float(geometry[-1]["lon"]), centre_lat, centre_lon)
        if not points or math.dist(points[-1], tail) > 2.0:
            points.append(tail)
    return points


def road_width(tags: dict) -> tuple[float, str]:
    try:
        width = float(str(tags.get("width", "0")).split(";")[0])
    except ValueError:
        width = 0.0
    if 2.0 < width < 30.0:
        return round(width, 2), "osm:width"
    try:
        lanes = int(float(str(tags.get("lanes", "0")).split(";")[0]))
    except ValueError:
        lanes = 0
    kind = str(tags.get("highway", ""))
    if lanes > 0:
        lane_width = 3.15 if kind in {"primary", "secondary", "tertiary"} else 2.85
        return round(min(max(lanes * lane_width, 3.0), 14.0), 2), "estimated:osm_lanes_x_class_lane_width"
    defaults = {
        "motorway": 11.0, "trunk": 11.0, "primary": 8.5, "secondary": 8.5,
        "tertiary": 7.0, "residential": 6.0, "unclassified": 6.0,
        "living_street": 6.0, "service": 4.5, "track": 3.4,
    }
    return defaults.get(kind, 4.8), "estimated:highway_class_default"


def building_record(element: dict, tags: dict, centre_lat: float, centre_lon: float) -> dict | None:
    footprint = geometry_points(element.get("geometry", []), centre_lat, centre_lon)
    if len(footprint) > 2 and footprint[0] == footprint[-1]:
        footprint.pop()
    if len(footprint) < 3:
        return None
    xs = [p[0] for p in footprint]
    zs = [p[1] for p in footprint]
    sx, sz = max(xs) - min(xs), max(zs) - min(zs)
    if sx < 2.0 or sz < 2.0 or sx > 120.0 or sz > 120.0:
        return None
    try:
        tagged_height = float(str(tags.get("height", "0")).replace(" m", ""))
    except ValueError:
        tagged_height = 0.0
    try:
        levels = float(str(tags.get("building:levels", "0")))
    except ValueError:
        levels = 0.0
    if tagged_height > 1.5:
        height, height_source = tagged_height, "osm:height"
    elif levels > 0:
        height, height_source = levels * 3.0, "estimated:osm_levels_x_3m"
    else:
        height, height_source = 6.0, "estimated:no_osm_height_default_6m"
    return {
        "osm_id": int(element["id"]),
        "center": [round((min(xs) + max(xs)) * 0.5, 3), round((min(zs) + max(zs)) * 0.5, 3)],
        "size": [round(sx, 3), round(sz, 3)],
        "footprint": footprint,
        "footprint_source": "osm:way_geometry",
        "height": round(min(max(height, 3.0), 48.0), 2),
        "height_source": height_source,
        "levels": levels,
        "kind": str(tags.get("building", "yes")),
        "material": str(tags.get("building:material", "")),
        "roof_shape": str(tags.get("roof:shape", "")),
        "roof_material": str(tags.get("roof:material", "")),
        "name": str(tags.get("name", "")),
        "addr_housenumber": str(tags.get("addr:housenumber", "")),
        "addr_street": str(tags.get("addr:street", "")),
        "amenity": str(tags.get("amenity", "")),
        "shop": str(tags.get("shop", "")),
    }


def build_patch(payload: dict, postcode: str, lat: float, lon: float, bbox: list[float]) -> dict:
    road_kinds = {"motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "service", "track"}
    path_kinds = {"footway", "path", "cycleway"}
    point_kinds = {"traffic_signals", "crossing", "bus_stop", "stop", "give_way"}
    roads, buildings, linear, points, pois = [], [], [], [], []
    for element in payload.get("elements", []):
        tags = element.get("tags", {})
        if element.get("type") == "node" and "lat" in element and "lon" in element:
            point = local_point(float(element["lat"]), float(element["lon"]), lat, lon)
            highway = str(tags.get("highway", ""))
            kind = "tree" if tags.get("natural") == "tree" else highway if highway in point_kinds else "traffic_sign" if "traffic_sign" in tags else ""
            if kind:
                points.append({"osm_id": int(element["id"]), "kind": kind, "point": point, "name": str(tags.get("name", "")), "crossing": str(tags.get("crossing", "")), "traffic_sign": str(tags.get("traffic_sign", "")), "ref": str(tags.get("ref", ""))})
            name = str(tags.get("name", "")).strip()
            if name:
                for key in ("amenity", "shop", "tourism", "leisure", "historic", "place"):
                    if key in tags:
                        pois.append({"osm_id": int(element["id"]), "kind": str(tags[key]), "name": name, "brand": str(tags.get("brand", "")), "operator": str(tags.get("operator", "")), "point": point})
                        break
            continue
        geometry = element.get("geometry", [])
        if len(geometry) < 2:
            continue
        highway = str(tags.get("highway", ""))
        if highway in road_kinds:
            pts = geometry_points(geometry, lat, lon)
            if len(pts) >= 2:
                width, width_source = road_width(tags)
                roads.append({"osm_id": int(element["id"]), "kind": highway, "name": str(tags.get("name", "")), "width": width, "width_source": width_source, "lanes": int(float(tags.get("lanes", 0))) if str(tags.get("lanes", "0")).replace(".", "", 1).isdigit() else 0, "oneway": str(tags.get("oneway", "no")), "surface": str(tags.get("surface", "")), "sidewalk": str(tags.get("sidewalk", "")), "lit": str(tags.get("lit", "")), "maxspeed": str(tags.get("maxspeed", "")), "ref": str(tags.get("ref", "")), "points": pts})
        elif "building" in tags:
            record = building_record(element, tags, lat, lon)
            if record:
                buildings.append(record)
        else:
            barrier = str(tags.get("barrier", ""))
            kind = barrier if barrier in {"hedge", "fence", "wall"} else highway if highway in path_kinds else ""
            if kind:
                pts = geometry_points(geometry, lat, lon)
                if len(pts) >= 2:
                    linear.append({"osm_id": int(element["id"]), "kind": kind, "surface": str(tags.get("surface", "")), "points": pts})
    def point_distance(item: dict) -> float:
        return math.hypot(*item["point"])

    def line_distance(item: dict) -> float:
        return min(math.hypot(*point) for point in item["points"])

    roads = sorted(roads, key=line_distance)[:220]
    buildings = sorted(buildings, key=lambda item: math.hypot(*item["center"]))[:320]
    linear = sorted(linear, key=line_distance)[:260]
    points = sorted(points, key=point_distance)[:260]
    pois = sorted(pois, key=point_distance)[:180]
    osm_meta = payload.get("osm3s", {})
    return {
        "patch_format": 1,
        "patch_id": "uk-edinburgh-eh15-2bz",
        "display_name": "EH15 2BZ · east Edinburgh",
        "source": "packaged_osm_patch",
        "source_name": "OpenStreetMap",
        "source_url": "https://www.openstreetmap.org/copyright",
        "source_timestamp_utc": str(osm_meta.get("timestamp_osm_base", "unknown")),
        "generated_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "license": "ODbL 1.0; © OpenStreetMap contributors",
        "start_postcode": postcode,
        "center_lat": lat,
        "center_lon": lon,
        "center_kind": "postcode_centroid_from_postcodes.io_quality_1_not_surveyed_window_position",
        "bbox": bbox,
        "dimension_notes": "Footprints are OSM way geometry. Heights and road widths carry per-feature source labels; estimated values are not surveyed dimensions.",
        "roads": roads,
        "buildings": buildings,
        "linear_features": linear,
        "point_features": points,
        "poi_features": pois,
        "updated_unix": int(datetime.now(timezone.utc).timestamp()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="godot/patches/eh15_2bz.json")
    parser.add_argument("--raw", help="Use an existing Overpass JSON response")
    args = parser.parse_args()
    half_lat, half_lon = 0.0060, 0.0100
    bbox = [DEFAULT_LAT - half_lat, DEFAULT_LON - half_lon, DEFAULT_LAT + half_lat, DEFAULT_LON + half_lon]
    if args.raw:
        payload = json.loads(Path(args.raw).read_text())
    else:
        box = ",".join(f"{v:.6f}" for v in bbox)
        query = f'[out:json][timeout:30];(way[highway~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|service|track|footway|path|cycleway)$"]({box});way[building]({box});way[barrier~"^(hedge|fence|wall)$"]({box});node[natural=tree]({box});node[highway~"^(traffic_signals|crossing|bus_stop|stop|give_way)$"]({box});node[traffic_sign]({box});node[amenity][name]({box});node[shop][name]({box});node[tourism][name]({box});node[leisure][name]({box});node[historic][name]({box});node[place][name]({box}););out tags geom qt;'
        url = "https://overpass-api.de/api/interpreter?" + urllib.parse.urlencode({"data": query})
        request = urllib.request.Request(url, headers={"User-Agent": "ProceedUntilApprehended/0.76 location-patch-builder"})
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.load(response)
    patch = build_patch(payload, DEFAULT_POSTCODE, DEFAULT_LAT, DEFAULT_LON, bbox)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    part_sizes = {"roads": 220, "buildings": 160, "linear_features": 260, "point_features": 260, "poi_features": 180}
    part_map: dict[str, list[str]] = {}
    for feature, chunk_size in part_sizes.items():
        items = patch.pop(feature)
        part_map[feature] = []
        for index in range(0, len(items), chunk_size):
            part_name = f"{output.stem}_{feature}_{index // chunk_size + 1}.json"
            part_map[feature].append(part_name)
            part_payload = {"patch_format": 1, "patch_id": patch["patch_id"], "feature": feature, "items": items[index:index + chunk_size]}
            (output.parent / part_name).write_text(json.dumps(part_payload, separators=(",", ":")) + "\n")
    patch["parts"] = part_map
    output.write_text(json.dumps(patch, separators=(",", ":")) + "\n")
    counts = {key: sum(len(json.loads((output.parent / name).read_text())["items"]) for name in names) for key, names in part_map.items()}
    print(json.dumps({"output": str(output), "roads": counts["roads"], "buildings": counts["buildings"], "source_timestamp_utc": patch["source_timestamp_utc"]}))


if __name__ == "__main__":
    main()
