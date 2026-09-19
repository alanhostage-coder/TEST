from pathlib import Path
import re

p = Path("android/app/src/main/assets/www/index.html")
s = p.read_text()

s = s.replace("build 0.8 LIVING CAMERA", "build 0.9 CHASE WORLD")
s = s.replace("build 0.8 · LIVING CAMERA", "build 0.9 · CHASE WORLD")
s = s.replace("Persistent procedural realm · build 0.8 · LIVING CAMERA", "Persistent procedural realm · build 0.9 · CHASE WORLD")
s = s.replace(
    "This pass removes more interface instead of adding more buttons. The camera now chases your heading, buildings lift out of the ground, speed changes the framing, old memories tint places rather than becoming objectives, and the realm quietly changes temperament over time.",
    "This pass drops the viewpoint behind the car: roads now fall toward a horizon, buildings and traffic scale with distance, speed stretches the chase view, and the world reads less like a map and more like somewhere you are driving through."
)

old = "function worldToScreen(x,y,cam){const dx=x-cam.x,dy=y-cam.y,cr=Math.cos(cam.rot||0),sr=Math.sin(cam.rot||0);return {x:(dx*cr-dy*sr)*cam.z+W/2,y:(dx*sr+dy*cr)*cam.z+H*.56}}"
new = """function worldToScreen(x,y,cam){const dx=x-cam.x,dy=y-cam.y;const side=dx*(-cam.fy)+dy*cam.fx;const depth=dx*cam.fx+dy*cam.fy;if(depth<cam.near||depth>cam.far)return {x:-9999,y:-9999,depth,scale:0,visible:false};const scale=cam.focal/depth;return {x:W*.5+side*scale,y:cam.horizon+cam.height*scale,depth,scale,visible:true}}"""
if old not in s:
    raise SystemExit("worldToScreen target missing")
s = s.replace(old, new)

old = "function fillWorldRect(x,y,w,h,col,cam){pathPoly([worldToScreen(x,y,cam),worldToScreen(x+w,y,cam),worldToScreen(x+w,y+h,cam),worldToScreen(x,y+h,cam)],col)}"
new = """function fillWorldRect(x,y,w,h,col,cam){const q=[worldToScreen(x,y,cam),worldToScreen(x+w,y,cam),worldToScreen(x+w,y+h,cam),worldToScreen(x,y+h,cam)];if(q.filter(p=>p.visible).length<3)return;pathPoly(q.filter(p=>p.visible),col)}"""
s = s.replace(old, new)

old = "function line(x1,y1,x2,y2,w,col,cam){const a=worldToScreen(x1,y1,cam),b=worldToScreen(x2,y2,cam);ctx.strokeStyle=col;ctx.lineWidth=w*cam.z;ctx.lineCap='round';ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke()}"
new = """function line(x1,y1,x2,y2,w,col,cam){const n=12;ctx.strokeStyle=col;ctx.lineCap='round';for(let i=0;i<n;i++){const t0=i/n,t1=(i+1)/n;const ax=x1+(x2-x1)*t0,ay=y1+(y2-y1)*t0,bx=x1+(x2-x1)*t1,by=y1+(y2-y1)*t1,a=worldToScreen(ax,ay,cam),b=worldToScreen(bx,by,cam);if(!a.visible||!b.visible)continue;ctx.lineWidth=Math.max(.5,w*(a.scale+b.scale)*.5);ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke()}}"""
s = s.replace(old, new)

pat = r"function drawBuilding\(b,cam\)\{.*?\}\nfunction entityName"
rep = """function drawBuilding(b,cam){const x=b.x-b.w/2,y=b.y-b.h/2,q=[worldToScreen(x,y,cam),worldToScreen(x+b.w,y,cam),worldToScreen(x+b.w,y+b.h,cam),worldToScreen(x,y+b.h,cam)];if(q.some(p=>!p.visible))return;const sc=q.reduce((a,p)=>a+p.scale,0)/4,hgt=(18+55*b.t)*sc,off={x:-hgt*.08,y:-hgt};const top=q.map(p=>({x:p.x+off.x,y:p.y+off.y}));const fade=Math.max(.2,1-(q[0].depth/cam.far)*.7);ctx.save();ctx.globalAlpha=fade;pathPoly([q[1],q[2],top[2],top[1]],b.t>.68?'#504b45':'#454946');pathPoly([q[2],q[3],top[3],top[2]],b.t>.68?'#5b554d':'#50534e');pathPoly(top,b.t>.68?'#797165':'#686d66','rgba(255,238,202,.08)');ctx.restore()}
function entityName"""
s, n = re.subn(pat, rep, s, count=1, flags=re.S)
if n != 1:
    raise SystemExit("drawBuilding target missing")

pat = r"function drawTraffic\(chunks,cam\)\{.*?\}\nfunction draw\(\)"
rep = """function drawTraffic(chunks,cam){const mood=worldMood(),t=state.playSeconds*.018,cars=[];for(const c of chunks)for(let ri=0;ri<c.roads.length;ri++){const r=c.roads[ri],base=1+(hash(c.cx*19+ri,c.cy,seed^0x454)>.68?1:0),count=Math.max(0,Math.round(base*mood.traffic));for(let j=0;j<count;j++){const speed=.045+hash(c.cx+ri,j+c.cy,seed^0x455)*.06,ph=(t*speed+hash(j,c.cx+c.cy,seed^0x456))%1,x=r.x1+(r.x2-r.x1)*ph,y=r.y1+(r.y2-r.y1)*ph,p=worldToScreen(x,y,cam);if(p.visible)cars.push({x,y,p,a:screenAngle(x,y,x+(r.x2-r.x1)*.05,y+(r.y2-r.y1)*.05,cam),name:entityName(c.cx,c.cy,ri,j),shade:hash(j,ri+c.cx,seed^0x457)>.5?'#8f9187':'#6f7778'})}}cars.sort((a,b)=>b.p.depth-a.p.depth);for(const car of cars){const z=Math.max(.12,car.p.scale);ctx.save();ctx.translate(car.p.x,car.p.y);ctx.rotate(car.a);ctx.fillStyle=car.shade;ctx.fillRect(-11*z,-5*z,22*z,10*z);ctx.fillStyle='rgba(230,215,180,.25)';ctx.fillRect(7*z,-4*z,2*z,3*z);ctx.restore();if(car.p.depth<260&&state.stillness>2){ctx.fillStyle='rgba(255,245,224,.64)';ctx.font='9px monospace';ctx.textAlign='center';ctx.fillText(car.name,car.p.x,car.p.y-9*z);ctx.textAlign='start'}}}
function draw()"""
s, n = re.subn(pat, rep, s, count=1, flags=re.S)
if n != 1:
    raise SystemExit("drawTraffic target missing")

pat = r"function draw\(\)\{const s=season\(\),w=weather\(\),speed=Math\.abs\(state\.v\),z=.*?;let sky="
rep = """function draw(){const s=season(),w=weather(),speed=Math.abs(state.v),fx=Math.cos(state.a),fy=Math.sin(state.a),back=state.onFoot?145:205+speed*7,cam={x:state.x-fx*back,y:state.y-fy*back,fx,fy,z:1,height:state.onFoot?100:142+speed*3.8,horizon:H*(state.onFoot?.36:.335-Math.min(.025,speed*.002)),focal:Math.min(W,H)*.47,near:28,far:3000};let sky="""
s, n = re.subn(pat, rep, s, count=1, flags=re.S)
if n != 1:
    raise SystemExit("draw header target missing")

s = s.replace(
    "ctx.fillStyle=sky;ctx.fillRect(0,0,W,H);",
    "const grd=ctx.createLinearGradient(0,0,0,H);grd.addColorStop(0,sky);grd.addColorStop(cam.horizon/H,sky);grd.addColorStop(Math.min(.98,cam.horizon/H+.08),'#747769');grd.addColorStop(1,'#4a4b43');ctx.fillStyle=grd;ctx.fillRect(0,0,W,H);",
    1
)

p.write_text(s)

bp = Path("android/app/build.gradle")
b = bp.read_text().replace("versionCode 8", "versionCode 9").replace("versionName '0.8'", "versionName '0.9'")
bp.write_text(b)

print("patched build 0.9", len(s))
