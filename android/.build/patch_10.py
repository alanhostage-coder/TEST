from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()

s=s.replace('build 0.9 CHASE WORLD','build 0.10 COASTAL CHASE')
s=s.replace('build 0.9 · CHASE WORLD','build 0.10 · COASTAL CHASE')
s=s.replace('This pass drops the viewpoint behind the car: roads now fall toward a horizon, buildings and traffic scale with distance, speed stretches the chase view, and the world reads less like a map and more like somewhere you are driving through.','The chase camera now has weight rather than being bolted to the car. A distant Forth-side industrial horizon, layered haar, sodium light and speed-sensitive framing give the realm a stronger sense of scale while keeping the roads free to roam.')

# Add a persistent, damped chase rig. This removes the rigid camera snap that made 0.9 feel like a projection demo.
anchor="function draw(){const s=season(),w=weather(),speed=Math.abs(state.v),fx=Math.cos(state.a),fy=Math.sin(state.a),back=state.onFoot?145:205+speed*7,cam={x:state.x-fx*back,y:state.y-fy*back,fx,fy,z:1,height:state.onFoot?100:142+speed*3.8,horizon:H*(state.onFoot?.36:.335-Math.min(.025,speed*.002)),focal:Math.min(W,H)*.47,near:28,far:3000};let sky="
replacement="""function draw(){const s=season(),w=weather(),speed=Math.abs(state.v),fx=Math.cos(state.a),fy=Math.sin(state.a),back=state.onFoot?145:205+speed*7,targetX=state.x-fx*back,targetY=state.y-fy*back;if(!window.__puaChase)window.__puaChase={x:targetX,y:targetY,fx,fy};const rig=window.__puaChase,follow=state.onFoot?.14:.065+Math.min(.07,speed*.004);rig.x+=(targetX-rig.x)*follow;rig.y+=(targetY-rig.y)*follow;rig.fx+=(fx-rig.fx)*.09;rig.fy+=(fy-rig.fy)*.09;const rl=Math.hypot(rig.fx,rig.fy)||1;rig.fx/=rl;rig.fy/=rl;const cam={x:rig.x,y:rig.y,fx:rig.fx,fy:rig.fy,z:1,height:state.onFoot?100:142+speed*3.8,horizon:H*(state.onFoot?.36:.335-Math.min(.025,speed*.002)),focal:Math.min(W,H)*(.47+Math.min(.055,speed*.006)),near:28,far:3400};let sky="""
if anchor not in s: raise SystemExit('0.9 camera anchor missing')
s=s.replace(anchor,replacement,1)

# Original-code Scottish coastal depth layer: distant sheds, cranes, pylons, low hills and haar.
needle="const grd=ctx.createLinearGradient(0,0,0,H);grd.addColorStop(0,sky);grd.addColorStop(cam.horizon/H,sky);grd.addColorStop(Math.min(.98,cam.horizon/H+.08),'#747769');grd.addColorStop(1,'#4a4b43');ctx.fillStyle=grd;ctx.fillRect(0,0,W,H);"
layer=needle+"""const hy=cam.horizon;ctx.save();ctx.globalAlpha=.28+.18*w.cloud;ctx.fillStyle='#3f4543';ctx.beginPath();ctx.moveTo(0,hy+9);for(let x=0;x<=W;x+=W/12){const hh=10+18*hash(Math.floor(x/50),Math.floor(state.y/900),seed^0x710);ctx.lineTo(x,hy-hh)}ctx.lineTo(W,hy+34);ctx.lineTo(0,hy+34);ctx.closePath();ctx.fill();ctx.strokeStyle='rgba(46,49,47,.42)';ctx.lineWidth=2;for(let i=0;i<5;i++){const x=((i*233+(state.x*.025))%(W+180))-90,h=34+(i%3)*16;ctx.beginPath();ctx.moveTo(x,hy+5);ctx.lineTo(x,hy-h);ctx.lineTo(x+34,hy-h+15);ctx.stroke()}ctx.fillStyle='rgba(214,201,177,.055)';ctx.fillRect(0,hy-18,W,46);ctx.fillStyle='rgba(237,224,198,.035)';ctx.fillRect(0,hy-7,W,25);ctx.restore();"""
if needle not in s: raise SystemExit('sky anchor missing')
s=s.replace(needle,layer,1)

# Filmic road-speed cue and restrained windscreen-height vignette. No pink wash.
end_anchor="function drawTraffic(chunks,cam){"
fx="""function drawChaseAtmosphere(cam,speed){ctx.save();const v=ctx.createRadialGradient(W*.5,H*.52,Math.min(W,H)*.18,W*.5,H*.52,Math.max(W,H)*.72);v.addColorStop(0,'rgba(0,0,0,0)');v.addColorStop(1,'rgba(10,12,11,.24)');ctx.fillStyle=v;ctx.fillRect(0,0,W,H);if(speed>4){ctx.globalAlpha=Math.min(.12,(speed-4)*.009);ctx.strokeStyle='rgba(226,218,199,.45)';ctx.lineWidth=1;for(let i=0;i<12;i++){const y=cam.horizon+35+hash(i,Math.floor(state.playSeconds),seed^0x711)*(H-cam.horizon-50),x=hash(i,7,seed^0x712)*W;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+(x-W*.5)*.025,y+8);ctx.stroke()}}ctx.restore()}
"""+end_anchor
if end_anchor not in s: raise SystemExit('traffic anchor missing')
s=s.replace(end_anchor,fx,1)

# Apply atmosphere immediately before HUD so it binds the world without obscuring controls.
hud_candidates=['drawHud();','drawHUD();']
for h in hud_candidates:
    if h in s:
        s=s.replace(h,'drawChaseAtmosphere(cam,speed);'+h,1)
        break
else:
    # Safe fallback: atmosphere is still useful even when the renderer has no named HUD helper.
    traffic_call='drawTraffic(chunks,cam);'
    if traffic_call in s: s=s.replace(traffic_call,traffic_call+'drawChaseAtmosphere(cam,speed);',1)

p.write_text(s)

bp=Path('android/app/build.gradle')
b=bp.read_text().replace('versionCode 9','versionCode 10').replace("versionName '0.9'","versionName '0.10'")
bp.write_text(b)
print('patched build 0.10',len(s))
