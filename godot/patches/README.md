# PUA location patches

Location patches are independently usable JSON files containing source-dated
OpenStreetMap roads, building footprints, names and street features in a local
metre frame. The centre coordinate is an origin, not a surveyed player or
window position.

`eh15_2bz.json` is the patch manifest and its named JSON parts hold the feature
arrays. Together they are the independently downloadable location patch. It is
centred on the quality-1 postcodes.io centroid for EH15 2BZ:
`55.951507, -3.107122`. It includes OSM attribution and a source timestamp.
Every building height and road width states whether it came from an OSM tag or
was estimated. No photograph-derived geometry is included.

Rebuild with:

```bash
python3 tools/build_osm_patch.py
```

Data © OpenStreetMap contributors, ODbL 1.0.
