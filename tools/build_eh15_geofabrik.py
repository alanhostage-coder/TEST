#!/usr/bin/env python3
import json, math, os
from datetime import datetime, timezone
from pathlib import Path

CENTER_LAT=55.951507
CENTER_LON=-3.107122
SOUTH,WEST,NORTH,EAST=55.9268,-3.1625,55.9845,-3.0660
LAT_STEP=0.0110
LON_STEP=0.0195
OUT=Path(os.environ.get("PUA_EH15_OUT","eh15_full"))
HIGHWAYS={"motorway","trunk","primary","secondary","tertiary","residential","unclassified","living_street","service","track"}
ATTENTION={"traffic_signals","crossing","bus_stop","stop","give_way"}

def local(lat,lon):
    return [(lon-CENTER_LON)*(111320.0*math.cos(math.radians(CENTER_LAT))), -(lat-CENTER_LAT)*111320.0]

def osm_id(props):
    raw=str(props.get("@id",props.get("id","0")))
    try:return int(raw.split("/")[-1])
    except:return 0

def props_clean(props):
    return {str(k):v for k,v in props.items() if not str(k).startswith("@")}

def road_width(tags):
    try: explicit=float(tags.get("width","0") or 0)
    except: explicit=0
    if 2<explicit<30:return explicit,"osm:width"
    kind=str(tags.get("highway",""))
    try: lanes=int(tags.get("lanes","0") or 0)
    except: lanes=0
    if lanes>0:
        lane=3.15 if kind in ("primary","secondary","tertiary") else 2.85
        return max(3,min(14,lanes*lane)),"estimated:osm_lanes_x_class_lane_width"
    return {"motorway":11,"trunk":11,"primary":8.5,"secondary":8.5,"tertiary":7,"residential":6,"unclassified":6,"living_street":6,"service":4.5,"track":3.4}.get(kind,4.8),"estimated:highway_class_default"

def points(coords,min_gap=.75):
    out=[];last=None
    for lon,lat,*_ in coords:
        p=local(float(lat),float(lon))
        if last is None or math.hypot(p[0]-last[0],p[1]-last[1])>=min_gap:
            out.append([round(p[0],3),round(p[1],3)]);last=p
    if len(coords)>1:
        lon,lat,*_=coords[-1];p=local(float(lat),float(lon))
        if not out or math.hypot(p[0]-out[-1][0],p[1]-out[-1][1])>2:
            out.append([round(p[0],3),round(p[1],3)])
    return out

def number(tags,key):
    try:return float(str(tags.get(key,"0")).split()[0])
    except:return 0.0

def building(tags,coords,oid):
    pts=points(coords,0.0)
    if len(pts)<3:return None
    if pts[0]==pts[-1]:pts=pts[:-1]
    xs=[p[0] for p in pts];zs=[p[1] for p in pts]
    sx=max(xs)-min(xs);sz=max(zs)-min(zs)
    if sx<2 or sz<2 or sx>220 or sz>220:return None
    levels=number(tags,"building:levels"); tagged=number(tags,"height")
    h=tagged if tagged>1.5 else max(3.2,levels*3.0)
    if h<=3.2:h=6.0
    return {"osm_id":oid,"center":[round((min(xs)+max(xs))/2,3),round((min(zs)+max(zs))/2,3)],
      "size":[round(sx,3),round(sz,3)],"footprint":pts,"height":round(max(3,min(48,h)),2),
      "footprint_source":"osm:way_geometry","height_source":"osm:height" if tagged>1.5 else ("estimated:osm_levels_x_3m" if levels>0 else "estimated:no_osm_height_default"),
      "levels":levels,"kind":str(tags.get("building","yes")),"material":str(tags.get("building:material","")),
      "roof_shape":str(tags.get("roof:shape","")),"roof_material":str(tags.get("roof:material","")),
      "name":str(tags.get("name","")),"addr_housenumber":str(tags.get("addr:housenumber","")),
      "addr_street":str(tags.get("addr:street","")),"amenity":str(tags.get("amenity","")),"shop":str(tags.get("shop",""))}

def tile_for_point(x,z,rows,cols):
    lat=CENTER_LAT-z/111320.0
    lon=CENTER_LON+x/(111320.0*math.cos(math.radians(CENTER_LAT)))
    iy=max(0,min(rows-1,int((lat-SOUTH)/LAT_STEP)))
    ix=max(0,min(cols-1,int((lon-WEST)/LON_STEP)))
    return f"{ix}_{iy}"

def feature_point(item):
    p=item.get("point") or item.get("center")
    if isinstance(p,list) and len(p)>=2:return float(p[0]),float(p[1])
    pts=item.get("points",[])
    if isinstance(pts,list) and pts:
        return sum(float(p[0]) for p in pts)/len(pts),sum(float(p[1]) for p in pts)/len(pts)
    fp=item.get("footprint",[])
    if isinstance(fp,list) and fp:
        return sum(float(p[0]) for p in fp)/len(fp),sum(float(p[1]) for p in fp)/len(fp)
    return 0.0,0.0



def point_segment_distance(p,a,b):
    vx=b[0]-a[0]; vy=b[1]-a[1]
    wx=p[0]-a[0]; wy=p[1]-a[1]
    denom=vx*vx+vy*vy
    t=max(0.0,min(1.0,(wx*vx+wy*vy)/denom)) if denom>1e-9 else 0.0
    qx=a[0]+t*vx; qy=a[1]+t*vy
    return math.hypot(p[0]-qx,p[1]-qy)

def cull_buildings_in_drivable_corridors(bytile):
    excluded={"service","track","path","footway","cycleway"}
    cell=40.0
    road_grid={}
    for tile in bytile.values():
        for road in tile["roads"]:
            if str(road.get("kind","")).lower() in excluded:
                continue
            width=float(road.get("width",5.0) or 5.0)
            pts=road.get("points",[])
            for i in range(len(pts)-1):
                a=pts[i]; b=pts[i+1]
                if len(a)<2 or len(b)<2: continue
                corridor=width*0.5+0.9
                minx=min(a[0],b[0])-corridor; maxx=max(a[0],b[0])+corridor
                minz=min(a[1],b[1])-corridor; maxz=max(a[1],b[1])+corridor
                seg=(a,b,corridor)
                for gx in range(math.floor(minx/cell),math.floor(maxx/cell)+1):
                    for gz in range(math.floor(minz/cell),math.floor(maxz/cell)+1):
                        road_grid.setdefault((gx,gz),[]).append(seg)
    culled=0
    for tile in bytile.values():
        kept=[]
        for bld in tile["buildings"]:
            fp=bld.get("footprint",[])
            if not isinstance(fp,list) or len(fp)<3:
                kept.append(bld); continue
            samples=[]
            for i,p in enumerate(fp):
                if not isinstance(p,list) or len(p)<2: continue
                q=fp[(i+1)%len(fp)]
                samples.append((float(p[0]),float(p[1])))
                if isinstance(q,list) and len(q)>=2:
                    samples.append(((float(p[0])+float(q[0]))*0.5,(float(p[1])+float(q[1]))*0.5))
            conflict=False
            checked=set()
            for p in samples:
                key=(math.floor(p[0]/cell),math.floor(p[1]/cell))
                for seg in road_grid.get(key,[]):
                    sid=id(seg)
                    if sid in checked: continue
                    checked.add(sid)
                    if point_segment_distance(p,seg[0],seg[1]) < seg[2]:
                        conflict=True; break
                if conflict: break
            if conflict:
                culled+=1
            else:
                kept.append(bld)
        tile["buildings"]=kept
    return culled

def dedupe_features(items):
    out=[]
    seen=set()
    for item in items:
        oid=int(item.get("osm_id",0))
        kind=str(item.get("kind",""))
        name=str(item.get("name",""))
        key=(oid,kind) if oid else (0,kind,name,json.dumps(item.get("point",item.get("center",item.get("points",[]))),separators=(",",":")))
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out

def build_destinations(outdir,tiles,source_timestamp):
    c={}
    for tile in tiles:
        for item,stype in [(x,"poi") for x in tile["poi_features"]]+[(x,"building") for x in tile["buildings"]]:
            name=str(item.get("name","")).strip()
            p=item.get("point") if stype=="poi" else item.get("center")
            if not name or not isinstance(p,list) or len(p)<2:continue
            kind=str(item.get("kind",stype));oid=int(item.get("osm_id",0))
            priority=10 if kind.startswith("historic:") else 9 if kind.startswith("tourism:") else 8 if kind.startswith("leisure:") else 7 if kind.startswith("amenity:") else 6 if stype=="building" else 4
            c[(stype,oid if oid else name)]={"osm_id":oid,"name":name,"kind":kind,"point":p,"source_type":stype,"priority":priority}
    cells={}
    for item in c.values():
        x,z=map(float,item["point"][:2]);cell=(math.floor(x/300),math.floor(z/300))
        old=cells.get(cell)
        if old is None or (item["priority"],len(item["name"]))>(old["priority"],len(old["name"])):cells[cell]=item
    remaining=list(cells.values());ordered=[];cur=[0.,0.]
    while remaining and len(ordered)<72:
        nxt=min(remaining,key=lambda i:abs(math.hypot(float(i["point"][0])-cur[0],float(i["point"][1])-cur[1])-600)-25*i["priority"])
        remaining.remove(nxt);clean={k:v for k,v in nxt.items() if k!="priority"};ordered.append(clean);cur=list(map(float,clean["point"][:2]))
    (outdir/"destinations.json").write_text(json.dumps({"source":"OpenStreetMap","source_url":"https://www.openstreetmap.org/copyright","license":"ODbL 1.0; © OpenStreetMap contributors","source_timestamp_utc":source_timestamp,"selection_note":"Names and coordinates come from bundled OSM named POIs/buildings; ordering is gameplay only.","destinations":ordered},separators=(",",":")))
    return len(ordered)

def main():
    path=Path(os.environ.get("EH15_GEOJSON","eh15.geojson"))
    fc=json.loads(path.read_text())
    rows=math.ceil((NORTH-SOUTH)/LAT_STEP);cols=math.ceil((EAST-WEST)/LON_STEP)
    bytile={}
    for iy in range(rows):
      for ix in range(cols):
        tid=f"{ix}_{iy}";s=SOUTH+iy*LAT_STEP;n=min(NORTH,s+LAT_STEP);w=WEST+ix*LON_STEP;e=min(EAST,w+LON_STEP)
        sw=local(s,w);ne=local(n,e)
        bytile[tid]={"patch_format":2,"patch_id":"uk-edinburgh-eh15-full","tile_id":tid,"source":"OpenStreetMap","source_url":"https://www.openstreetmap.org/copyright","license":"ODbL 1.0; © OpenStreetMap contributors","bbox":[s,w,n,e],"roads":[],"buildings":[],"linear_features":[],"point_features":[],"poi_features":[],"identity_features":[],"local_bounds":[min(sw[0],ne[0]),min(sw[1],ne[1]),max(sw[0],ne[0]),max(sw[1],ne[1])]}
    for f in fc.get("features",[]):
        props=props_clean(f.get("properties") or {});geom=f.get("geometry") or {};typ=geom.get("type","");coords=geom.get("coordinates") or [];oid=osm_id(f.get("properties") or {})
        item=None;key=None
        if typ=="Point":
            lon,lat,*_=coords;p=local(lat,lon);highway=str(props.get("highway",""))
            if props.get("natural")=="tree" or highway in ATTENTION or "traffic_sign" in props:
                item={"osm_id":oid,"kind":"tree" if props.get("natural")=="tree" else ("traffic_sign" if "traffic_sign" in props and not highway else highway),"name":str(props.get("name","")),"traffic_sign":str(props.get("traffic_sign","")),"point":[round(p[0],3),round(p[1],3)]};key="point_features"
            if props.get("name") and any(k in props for k in ("amenity","shop","tourism","leisure","historic","place")):
                kind=next((k+":"+str(props[k]) for k in ("amenity","shop","tourism","leisure","historic","place") if k in props),"poi")
                poi={"osm_id":oid,"kind":kind,"name":str(props.get("name","")),"point":[round(p[0],3),round(p[1],3)]}
                x,z=feature_point(poi);bytile[tile_for_point(x,z,rows,cols)]["poi_features"].append(poi)
            if item:
                x,z=feature_point(item);bytile[tile_for_point(x,z,rows,cols)][key].append(item)
            continue
        linecoords=coords
        if typ=="MultiLineString":linecoords=max(coords,key=len,default=[])
        if typ=="Polygon":linecoords=coords[0] if coords else []
        if typ=="MultiPolygon":linecoords=coords[0][0] if coords and coords[0] else []
        highway=str(props.get("highway",""))
        natural=str(props.get("natural",""))
        leisure=str(props.get("leisure",""))
        landuse=str(props.get("landuse",""))
        railway=str(props.get("railway",""))
        identity_kind=""
        identity_closed=typ in ("Polygon","MultiPolygon")
        if natural=="coastline":
            identity_kind="coastline"; identity_closed=False
        elif natural=="beach":
            identity_kind="beach"
        elif natural=="water":
            identity_kind="water"
        elif leisure in ("park","nature_reserve","recreation_ground"):
            identity_kind="open_space"
        elif landuse in ("grass","meadow","recreation_ground","cemetery"):
            identity_kind="open_space"
        elif landuse=="retail":
            identity_kind="retail_zone"
        elif landuse=="industrial":
            identity_kind="industrial_zone"
        elif landuse=="commercial":
            identity_kind="commercial_zone"
        elif railway in ("rail","light_rail"):
            identity_kind="railway"; identity_closed=False
        if identity_kind and linecoords:
            pts=points(linecoords,0.5 if identity_kind=="coastline" else 1.25)
            if len(pts)>=2:
                item={"osm_id":oid,"kind":identity_kind,"name":str(props.get("name","")),
                    "points":pts,"closed":bool(identity_closed),
                    "source_tag":"natural="+natural if natural else ("leisure="+leisure if leisure else ("landuse="+landuse if landuse else "railway="+railway))}
                key="identity_features"
        elif highway in HIGHWAYS and linecoords:
            pts=points(linecoords)
            if len(pts)>=2:
                width,ws=road_width(props)
                item={"osm_id":oid,"kind":highway,"name":str(props.get("name","")),"width":round(width,2),"width_source":ws,"lanes":int(props.get("lanes","0") or 0) if str(props.get("lanes","0") or "0").isdigit() else 0,"oneway":str(props.get("oneway","no")),"surface":str(props.get("surface","")),"sidewalk":str(props.get("sidewalk","")),"lit":str(props.get("lit","")),"maxspeed":str(props.get("maxspeed","")),"ref":str(props.get("ref","")),"points":pts};key="roads"
        elif "building" in props and linecoords:
            item=building(props,linecoords,oid);key="buildings"
        elif linecoords:
            barrier=str(props.get("barrier",""))
            if barrier in ("hedge","fence","wall") or highway in ("footway","path","cycleway"):
                pts=points(linecoords)
                if len(pts)>=2:item={"osm_id":oid,"kind":barrier if barrier else highway,"surface":str(props.get("surface","")),"points":pts};key="linear_features"
        if item and key:
            x,z=feature_point(item);bytile[tile_for_point(x,z,rows,cols)][key].append(item)
    road_conflict_culled=cull_buildings_in_drivable_corridors(bytile)
    OUT.mkdir(parents=True,exist_ok=True)
    source_timestamp=os.environ.get("OSM_SOURCE_TIMESTAMP","")
    tiles=[];records=[];totals={k:0 for k in ("roads","buildings","linear_features","point_features","poi_features","identity_features")}
    identity_kind_totals={}
    for tid,tile in bytile.items():
        for feature_key in ("roads","buildings","linear_features","point_features","poi_features","identity_features"):
            tile[feature_key]=dedupe_features(tile[feature_key])
        fn=f"tile_{tid}.json";(OUT/fn).write_text(json.dumps({k:v for k,v in tile.items() if k!="local_bounds"},separators=(",",":")))
        counts={k:len(tile[k]) for k in totals}
        for k,v in counts.items():totals[k]+=v
        for feature in tile["identity_features"]:
            kind=str(feature.get("kind",""))
            identity_kind_totals[kind]=identity_kind_totals.get(kind,0)+1
        records.append(tile);tiles.append({"id":tid,"file":fn,"bbox":tile["bbox"],"local_bounds":tile["local_bounds"],"counts":counts})
    dest=build_destinations(OUT,records,source_timestamp)
    manifest={"patch_format":2,"patch_id":"uk-edinburgh-eh15-full","display_name":"EH15 · Edinburgh","source":"packaged_osm_tiles","source_name":"OpenStreetMap via Geofabrik Scotland extract","source_url":"https://download.geofabrik.de/europe/united-kingdom/scotland.html","source_timestamp_utc":source_timestamp,"generated_utc":datetime.now(timezone.utc).isoformat(),"license":"ODbL 1.0; © OpenStreetMap contributors","start_postcode":"EH15","center_lat":CENTER_LAT,"center_lon":CENTER_LON,"coverage_bbox":[SOUTH,WEST,NORTH,EAST],"coverage_note":"Conservative envelope covers EH15 plus a small fringe; not asserted as an official postal boundary.","tile_rows":rows,"tile_cols":cols,"tiles":tiles,"raw_tile_totals":totals,"identity_kind_totals":identity_kind_totals,"dedupe_policy":"osm_id+kind per tile","road_conflict_policy":"offline_nonservice_corridor_cull_v1","road_conflict_culled":road_conflict_culled,"destination_count":dest}
    (OUT/"manifest.json").write_text(json.dumps(manifest,separators=(",",":")))
    print(json.dumps({"tiles":len(tiles),"totals":totals,"identity_kinds":identity_kind_totals,"road_conflict_culled":road_conflict_culled,"destinations":dest,"source_timestamp":source_timestamp},indent=2))
if __name__=="__main__":main()
