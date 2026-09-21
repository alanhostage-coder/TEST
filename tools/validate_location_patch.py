#!/usr/bin/env python3
"""Validate a PUA location patch without contacting its upstream services."""

from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any


FEATURE_TYPES = ("roads", "buildings", "linear_features", "point_features", "poi_features")


def fail(message: str) -> None:
    raise ValueError(message)


def finite_number(value: Any, label: str) -> float:
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        fail(f"{label} must be a finite number")
    return float(value)


def point(value: Any, label: str) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) < 2:
        fail(f"{label} must contain x and z")
    x = finite_number(value[0], f"{label}.x")
    z = finite_number(value[1], f"{label}.z")
    if abs(x) > 2500.0 or abs(z) > 2500.0:
        fail(f"{label} lies outside the supported local patch frame")
    return x, z


def load_patch(manifest_path: Path) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    parts = manifest.get("parts")
    if not isinstance(parts, dict):
        fail("manifest.parts is required")
    for feature in FEATURE_TYPES:
        names = parts.get(feature)
        if not isinstance(names, list) or not names:
            fail(f"manifest.parts.{feature} must name at least one part")
        items: list[dict[str, Any]] = []
        for name in names:
            part_path = manifest_path.parent / str(name)
            if not part_path.is_file():
                fail(f"missing part: {name}")
            part = json.loads(part_path.read_text(encoding="utf-8"))
            if part.get("patch_id") != manifest.get("patch_id"):
                fail(f"{name} has the wrong patch_id")
            if part.get("feature") != feature:
                fail(f"{name} claims the wrong feature type")
            rows = part.get("items")
            if not isinstance(rows, list):
                fail(f"{name}.items must be an array")
            items.extend(rows)
        manifest[feature] = items
    return manifest


def validate(manifest_path: Path) -> dict[str, Any]:
    patch = load_patch(manifest_path)
    if patch.get("start_postcode") != "EH15 2BZ":
        fail("this patch must identify EH15 2BZ exactly")
    if abs(finite_number(patch.get("center_lat"), "center_lat") - 55.951507) > 0.000001:
        fail("EH15 latitude is not the verified postcode centroid")
    if abs(finite_number(patch.get("center_lon"), "center_lon") + 3.107122) > 0.000001:
        fail("EH15 longitude is not the verified postcode centroid")
    if "not_surveyed" not in str(patch.get("center_kind", "")):
        fail("centroid must be labelled as not surveyed")
    if "openstreetmap.org/copyright" not in str(patch.get("source_url", "")).lower():
        fail("OpenStreetMap copyright URL is missing")
    if "odbl" not in str(patch.get("license", "")).lower():
        fail("ODbL licence declaration is missing")
    timestamp = str(patch.get("source_timestamp_utc", ""))
    try:
        datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError as exc:
        fail(f"invalid source_timestamp_utc: {exc}")

    road_ids: set[int] = set()
    road_nodes: dict[tuple[int, int], set[int]] = defaultdict(set)
    segment_count = 0
    named_road_count = 0
    for index, road in enumerate(patch["roads"]):
        if not isinstance(road, dict):
            fail(f"roads[{index}] must be an object")
        osm_id = int(road.get("osm_id", 0))
        if osm_id <= 0:
            fail(f"roads[{index}] has no positive OSM id")
        if osm_id in road_ids:
            fail(f"duplicate road OSM id {osm_id}")
        road_ids.add(osm_id)
        width = finite_number(road.get("width"), f"roads[{index}].width")
        if width <= 0.5 or not str(road.get("width_source", "")):
            fail(f"roads[{index}] has an unlabelled or invalid width")
        points = road.get("points")
        if not isinstance(points, list) or len(points) < 2:
            fail(f"roads[{index}] needs at least two points")
        previous: tuple[float, float] | None = None
        for point_index, raw_point in enumerate(points):
            current = point(raw_point, f"roads[{index}].points[{point_index}]")
            road_nodes[(round(current[0] * 10), round(current[1] * 10))].add(osm_id)
            if previous is not None:
                if math.dist(previous, current) < 0.01:
                    fail(f"roads[{index}] contains a zero-length segment")
                segment_count += 1
            previous = current
        if str(road.get("name", "")).strip():
            named_road_count += 1

    building_ids: set[int] = set()
    tagged_height_count = 0
    furthest_building_center_m = 0.0
    for index, building in enumerate(patch["buildings"]):
        if not isinstance(building, dict):
            fail(f"buildings[{index}] must be an object")
        osm_id = int(building.get("osm_id", 0))
        if osm_id <= 0 or osm_id in building_ids:
            fail(f"buildings[{index}] has a missing or duplicate OSM id")
        building_ids.add(osm_id)
        footprint = building.get("footprint")
        if not isinstance(footprint, list) or len(footprint) < 3:
            fail(f"buildings[{index}] needs a polygon footprint")
        coords = [point(value, f"buildings[{index}].footprint") for value in footprint]
        height = finite_number(building.get("height"), f"buildings[{index}].height")
        height_source = str(building.get("height_source", ""))
        if height < 2.0 or not height_source:
            fail(f"buildings[{index}] has an unlabelled or invalid height")
        if height_source.startswith("osm:"):
            tagged_height_count += 1
        center = point(building.get("center"), f"buildings[{index}].center")
        furthest_building_center_m = max(furthest_building_center_m, math.hypot(*center))
        size = point(building.get("size"), f"buildings[{index}].size")
        min_x, max_x = min(x for x, _ in coords), max(x for x, _ in coords)
        min_z, max_z = min(z for _, z in coords), max(z for _, z in coords)
        expected = ((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
        expected_size = (max_x - min_x, max_z - min_z)
        if math.dist(center, expected) > 0.05 or math.dist(size, expected_size) > 0.05:
            fail(f"buildings[{index}] bounds do not match its OSM footprint")

    for feature in ("linear_features",):
        for index, item in enumerate(patch[feature]):
            points = item.get("points") if isinstance(item, dict) else None
            if not isinstance(points, list) or len(points) < 2:
                fail(f"{feature}[{index}] needs at least two points")
            for point_index, raw_point in enumerate(points):
                point(raw_point, f"{feature}[{index}].points[{point_index}]")
    for feature in ("point_features", "poi_features"):
        for index, item in enumerate(patch[feature]):
            if not isinstance(item, dict):
                fail(f"{feature}[{index}] must be an object")
            point(item.get("point"), f"{feature}[{index}].point")

    junction_count = sum(1 for road_set in road_nodes.values() if len(road_set) > 1)
    named_poi_count = sum(bool(str(item.get("name", "")).strip()) for item in patch["poi_features"])
    if len(patch["roads"]) < 100 or len(patch["buildings"]) < 100:
        fail("patch is too sparse for the EH15 playable baseline")
    if named_road_count < 50 or named_poi_count < 50 or junction_count < 25:
        fail("patch lacks sufficient names or shared-road junction topology")
    if not any(road.get("name") == "Pittville Street" for road in patch["roads"]):
        fail("Pittville Street is absent from the EH15 patch")

    return {
        "validation_status": "passed",
        "patch_id": patch.get("patch_id"),
        "source": patch.get("source_name"),
        "source_timestamp_utc": timestamp,
        "licence": patch.get("license"),
        "postcode": patch.get("start_postcode"),
        "centroid": [patch.get("center_lat"), patch.get("center_lon")],
        "centroid_is_surveyed_position": False,
        "counts": {feature: len(patch[feature]) for feature in FEATURE_TYPES},
        "road_segments": segment_count,
        "shared_road_junction_nodes": junction_count,
        "named_roads": named_road_count,
        "named_pois": named_poi_count,
        "osm_tagged_building_heights": tagged_height_count,
        "estimated_building_heights": len(patch["buildings"]) - tagged_height_count,
        "furthest_building_center_m": round(furthest_building_center_m, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "manifest",
        nargs="?",
        type=Path,
        default=Path("godot/patches/eh15_2bz.json"),
    )
    parser.add_argument("--json", type=Path, help="also write the validation report")
    args = parser.parse_args()
    report = validate(args.manifest)
    rendered = json.dumps(report, indent=2, sort_keys=True)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
