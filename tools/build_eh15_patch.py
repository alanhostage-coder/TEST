#!/usr/bin/env python3
import json, math, os, time, urllib.parse, urllib.request
from datetime import datetime, timezone
from pathlib import Path

CENTER_LAT = 55.951507
CENTER_LON = -3.107122
# Coverage envelope contains the full EH15 postcode-district polygon plus a tiny edge margin.
# It is a streaming/data envelope, not an asserted surveyed boundary.
SOUTH, WEST, NORTH, EAST = 55.9268, -3.1625, 55.9845, -3.0660
LAT_STEP = 0.0110
LON_STEP = 0.0195
OUT = Path(os.environ.get("PUA_EH15_OUT", "eh15_full"))
ENDPOINTS = [
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]
HIGHWAYS = "motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|service|track"
ATTENTION = "traffic_signals|crossing|bus_stop|stop|give_way"

def local(lat, lon):
    mplon = 111320.0 * math.cos(math.radians(CENTER_LAT))
    return [(lon - CENTER_LON) * mplon, -(lat - CENTER_LAT) * 111320.0]

def _overpass_query(query):
    body = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(6):
        endpoint = ENDPOINTS[attempt % len(ENDPOINTS)]
        try:
            req = urllib.request.Request(endpoint, data=body, headers={"User-Agent":"PUA-EH15-builder/0.78","Accept":"application/json"})
            with urllib.request.urlopen(req, timeout=95) as resp:
                return json.load(resp)
        except Exception as exc:
            last = exc
            time.sleep(1.5 + attempt * 1.5)
    raise RuntimeError(f"Overpass failed: {last}")

def request_overpass(s, w, n, e):
    heavy = f'''[out:json][timeout:75][maxsize:536870912];
(
 way[highway~"^({HIGHWAYS})$"]({s},{w},{n},{e});
 way[building]({s},{w},{n},{e});
);
out tags geom qt;'''
    detail = f'''[out:json][timeout:60][maxsize:268435456];
(
 way[barrier~"^(hedge|fence|wall)$"]({s},{w},{n},{e});
 way[highway~"^(footway|path|cycleway)$"]({s},{w},{n},{e});
 node[natural=tree]({s},{w},{n},{e});
 node[highway~"^({ATTENTION})$"]({s},{w},{n},{e});
 node[traffic_sign]({s},{w},{n},{e});
 node[amenity][name]({s},{w},{n},{e});
 node[shop][name]({s},{w},{n},{e});
 node[tourism][name]({s},{w},{n},{e});
 node[leisure][name]({s},{w},{n},{e});
 node[historic][name]({s},{w},{n},{e});
 node[place][name]({s},{w},{n},{e});
);
out tags geom qt;'''
    a = _overpass_query(heavy)
    b = _overpass_query(detail)
    timestamp = max(str((a.get("osm3s") or {}).get("timestamp_osm_base","")), str((b.get("osm3s") or {}).get("timestamp_osm_base","")))
    return {"version":0.6,"osm3s":{"timestamp_osm_base":timestamp},"elements":a.get("elements",[])+b.get("elements",[])}

def geom_points(geom, min_gap=0.75):
    out=[]; last=None
    for g in geom or []:
        if not isinstance(g, dict): continue
        p=local(float(g.get("lat",CENTER_LAT)), float(g.get("lon",CENTER_LON)))
        if last is None or math.hypot(p[0]-last[0],p[1]-last[1]) >= min_gap:
            out.append([round(p[0],3),round(p[1],3)]); last=p
    if len(geom or []) > 1:
        g=geom[-1]
        if isinstance(g,dict):
            p=local(float(g.get("lat",CENTER_LAT)), float(g.get("lon",CENTER_LON)))
            if not out or math.hypot(p[0]-out[-1][0],p[1]-out[-1][1]) > 2.0:
                out.append([round(p[0],3),round(p[1],3)])
    return out

def road_width(tags):
    try: explicit=float(tags.get("width","0") or 0)
    except: explicit=0
    if 2 < explicit < 30: return explicit, "osm:width"
    kind=tags.get("highway","")
    try: lanes=int(tags.get("lanes","0") or 0)
    except: lanes=0
    if lanes>0:
        lw=3.15 if kind in ("primary","secondary","tertiary") else 2.85
        return max(3,min(14,lanes*lw)), "estimated:osm_lanes_x_class_lane_width"
    return {"motorway":11,"trunk":11,"primary":8.5,"secondary":8.5,"tertiary":7,
            "residential":6,"unclassified":6,"living_street":6,"service":4.5,"track":3.4}.get(kind,4.8), "estimated:highway_class_default"

def building(tags, geom, osm_id):
    pts=geom_points(geom,0.0)
    if len(pts)<3: return None
    xs=[p[0] for p in pts]; zs=[p[1] for p in pts]
    sx=max(xs)-min(xs); sz=max(zs)-min(zs)
    if sx<2 or sz<2 or sx>180 or sz>180: return None
    if pts[0]==pts[-1]: pts=pts[:-1]
    def num(k):
        try: return float(str(tags.get(k,"0")).split()[0])
        except: return 0.0
    levels=num("building:levels"); tagged=num("height")
    h=tagged if tagged>1.5 else max(3.2,levels*3.0)
    if h<=3.2: h=6.0
    h=max(3,min(48,h))
    return {"osm_id":osm_id,"center":[round((min(xs)+max(xs))/2,3),round((min(zs)+max(zs))/2,3)],
            "size":[round(sx,3),round(sz,3)],"footprint":pts,"height":round(h,2),
            "footprint_source":"osm:way_geometry",
            "height_source":"osm:height" if tagged>1.5 else ("estimated:osm_levels_x_3m" if levels>0 else "estimated:no_osm_height_default"),
            "levels":levels,"kind":str(tags.get("building","yes")),"material":str(tags.get("building:material","")),
            "roof_shape":str(tags.get("roof:shape","")),"roof_material":str(tags.get("roof:material","")),
            "name":str(tags.get("name","")),"addr_housenumber":str(tags.get("addr:housenumber","")),
            "addr_street":str(tags.get("addr:street","")),"amenity":str(tags.get("amenity","")),"shop":str(tags.get("shop",""))}

def parse(payload):
    roads=[]; buildings=[]; linear=[]; points=[]; pois=[]
    for el in payload.get("elements",[]):
        tags=el.get("tags") or {}; typ=el.get("type",""); oid=int(el.get("id",0))
        if typ=="node":
            lat=el.get("lat"); lon=el.get("lon")
            if lat is None or lon is None: continue
            p=local(float(lat),float(lon))
            h=str(tags.get("highway",""))
            if h in ("traffic_signals","crossing","bus_stop","stop","give_way") or "traffic_sign" in tags or tags.get("natural")=="tree":
                points.append({"osm_id":oid,"kind":"tree" if tags.get("natural")=="tree" else ("traffic_sign" if "traffic_sign" in tags and not h else h),
                    "name":str(tags.get("name","")),"traffic_sign":str(tags.get("traffic_sign","")),
                    "point":[round(p[0],3),round(p[1],3)]})
            if tags.get("name") and any(k in tags for k in ("amenity","shop","tourism","leisure","historic","place")):
                kind=next((k+":"+str(tags[k]) for k in ("amenity","shop","tourism","leisure","historic","place") if k in tags),"poi")
                pois.append({"osm_id":oid,"kind":kind,"name":str(tags.get("name","")),
                    "point":[round(p[0],3),round(p[1],3)]})
            continue
        if typ!="way": continue
        geom=el.get("geometry") or []
        highway=str(tags.get("highway",""))
        if highway and highway in HIGHWAYS.split("|"):
            pts=geom_points(geom)
            if len(pts)>=2:
                width,ws=road_width(tags)
                roads.append({"osm_id":oid,"kind":highway,"name":str(tags.get("name","")),"width":round(width,2),
                    "width_source":ws,"lanes":int(tags.get("lanes","0") or 0) if str(tags.get("lanes","0") or "0").isdigit() else 0,
                    "oneway":str(tags.get("oneway","no")),"surface":str(tags.get("surface","")),"sidewalk":str(tags.get("sidewalk","")),
                    "lit":str(tags.get("lit","")),"maxspeed":str(tags.get("maxspeed","")),"ref":str(tags.get("ref","")),"points":pts})
        elif "building" in tags:
            b=building(tags,geom,oid)
            if b: buildings.append(b)
        else:
            barrier=str(tags.get("barrier",""))
            if barrier in ("hedge","fence","wall") or highway in ("footway","path","cycleway"):
                pts=geom_points(geom)
                if len(pts)>=2:
                    linear.append({"osm_id":oid,"kind":barrier if barrier else highway,"surface":str(tags.get("surface","")),"points":pts})
    return roads,buildings,linear,points,pois

def dedupe(items):
    out=[]; seen=set()
    for x in items:
        key=(x.get("osm_id"),x.get("kind",""),x.get("name",""))
        if key in seen: continue
        seen.add(key); out.append(x)
    return out

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=math.ceil((NORTH-SOUTH)/LAT_STEP); cols=math.ceil((EAST-WEST)/LON_STEP)
    tiles=[]; totals={"roads":0,"buildings":0,"linear_features":0,"point_features":0,"poi_features":0}
    newest=""
    for iy in range(rows):
        s=SOUTH+iy*LAT_STEP; n=min(NORTH,s+LAT_STEP)
        for ix in range(cols):
            w=WEST+ix*LON_STEP; e=min(EAST,w+LON_STEP)
            tid=f"{ix}_{iy}"
            print(f"tile {tid} {s:.6f},{w:.6f},{n:.6f},{e:.6f}",flush=True)
            payload=request_overpass(s,w,n,e)
            newest=max(newest,str((payload.get("osm3s") or {}).get("timestamp_osm_base","")))
            roads,buildings,linear,points,pois=parse(payload)
            roads=dedupe(roads); buildings=dedupe(buildings); linear=dedupe(linear); points=dedupe(points); pois=dedupe(pois)
            tile={"patch_format":2,"patch_id":"uk-edinburgh-eh15-full","tile_id":tid,
                "source":"OpenStreetMap","source_url":"https://www.openstreetmap.org/copyright",
                "license":"ODbL 1.0; © OpenStreetMap contributors","source_timestamp_utc":newest,
                "bbox":[s,w,n,e],"roads":roads,"buildings":buildings,"linear_features":linear,"point_features":points,"poi_features":pois}
            fn=f"tile_{tid}.json"; (OUT/fn).write_text(json.dumps(tile,separators=(",",":")))
            counts={k:len(tile[k]) for k in totals}
            for k,v in counts.items(): totals[k]+=v
            sw=local(s,w); ne=local(n,e)
            tiles.append({"id":tid,"file":fn,"bbox":[s,w,n,e],
                "local_bounds":[min(sw[0],ne[0]),min(sw[1],ne[1]),max(sw[0],ne[0]),max(sw[1],ne[1])],"counts":counts})
            time.sleep(0.25)
    manifest={"patch_format":2,"patch_id":"uk-edinburgh-eh15-full","display_name":"EH15 · Edinburgh",
        "source":"packaged_osm_tiles","source_name":"OpenStreetMap","source_url":"https://www.openstreetmap.org/copyright",
        "source_timestamp_utc":newest,"generated_utc":datetime.now(timezone.utc).isoformat(),
        "license":"ODbL 1.0; © OpenStreetMap contributors","start_postcode":"EH15",
        "center_lat":CENTER_LAT,"center_lon":CENTER_LON,
        "coverage_bbox":[SOUTH,WEST,NORTH,EAST],
        "coverage_note":"Envelope deliberately extends beyond the EH15 district edges so the complete district is covered; it is not rendered as an asserted postal boundary.",
        "postcode_reference":"EH15 polygon reference cross-checked against National Records of Scotland postcode-district dataset metadata; runtime geometry is OSM only.",
        "tile_rows":rows,"tile_cols":cols,"tiles":tiles,"raw_tile_totals":totals}
    (OUT/"manifest.json").write_text(json.dumps(manifest,separators=(",",":")))
    print(json.dumps({"tiles":len(tiles),"totals":totals,"osm_timestamp":newest},indent=2))

if __name__=="__main__": main()
