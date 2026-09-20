from pathlib import Path
p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()

s=s.replace('build 0.21 MOTION + SOUND','build 0.22 BOOT RESCUE').replace('build 0.21 · MOTION + SOUND','build 0.22 · BOOT RESCUE')

mig="const MIG18='proceed-until-apprehended-migration-018-'+seedHex;if(!localStorage.getItem(MIG18)){const nr=nearestRoadPoint18(state.x,state.y);if(nr&&nr.d>54){state.x=nr.x;state.y=nr.y;state.a=Math.atan2(nr.r.y2-nr.r.y1,nr.r.x2-nr.r.x1);state.v=0}localStorage.setItem(MIG18,'1')}"
if mig not in s:
    raise SystemExit('migration block missing')
s=s.replace(mig,'',1)

anchor="function nearestRoadPoint18(x,y){let best=null,bd=1e9;for(const c of chunksAround(x,y,2))for(const r of c.roads){const dx=r.x2-r.x1,dy=r.y2-r.y1,l2=dx*dx+dy*dy||1,t=Math.max(0,Math.min(1,((x-r.x1)*dx+(y-r.y1)*dy)/l2)),px=r.x1+t*dx,py=r.y1+t*dy,d=Math.hypot(x-px,y-py);if(d<bd){bd=d;best={x:px,y:py,d,r}}}return best}"
if anchor not in s:
    raise SystemExit('nearest road anchor missing')
s=s.replace(anchor,anchor+"\\n"+mig,1)

old="document.getElementById('go').onclick=()=>{initAudio();document.getElementById('start').style.display='none';running=true;last=performance.now();wakeHud(6500);log(offlineAdvance>8?'The realm moved on for a while without you. Proceed until apprehended.':'Nothing is waiting for you. Proceed until apprehended.');requestAnimationFrame(loop)};"
new="document.getElementById('go').onclick=()=>{document.getElementById('start').style.display='none';running=true;last=performance.now();try{initAudio();if(AC&&AC.state==='suspended'&&AC.resume)AC.resume()}catch(e){console.warn('audio start failed',e)}wakeHud(6500);log(offlineAdvance>8?'The realm moved on for a while without you. Proceed until apprehended.':'Nothing is waiting for you. Proceed until apprehended.');requestAnimationFrame(loop)};"
if old not in s:
    raise SystemExit('Proceed handler anchor missing')
s=s.replace(old,new,1)

s=s.replace('Motion-and-sound pass: a second engine harmonic, road texture, wind and rain layers now respond to speed and surface, while frame-time-aware detail scaling protects the richer world on actual Android hardware.','Boot-rescue pass: the migration that could execute before the road system existed has been moved behind road initialisation, and Proceed no longer depends on audio starting successfully.')

p.write_text(s)

bp=Path('android/app/build.gradle')
b=bp.read_text().replace('versionCode 21','versionCode 22').replace("versionName '0.21'","versionName '0.22'")
bp.write_text(b)
print('patched build 0.22 BOOT RESCUE',len(s))
