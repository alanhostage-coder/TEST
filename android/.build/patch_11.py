from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()
s=s.replace('build 0.10 COASTAL CHASE','build 0.11 LIVING ROADS').replace('build 0.10 · COASTAL CHASE','build 0.11 · LIVING ROADS')

# Add road furniture and spontaneous roadside incidents projected into the chase view.
anchor='function drawTraffic(chunks,cam){'
addition=r'''function drawLivingRoad(cam,speed){
  const t=Math.floor(state.playSeconds/22), fx=cam.fx,fy=cam.fy, rx=-fy,ry=fx;
  ctx.save();
  // Repeating original roadside furniture gives scale and motion without heavy assets.
  for(let i=0;i<18;i++){
    const d=150+i*145-((state.playSeconds*Math.max(8,speed*12))%145), side=i%2?1:-1;
    if(d<cam.near)continue;
    const wx=state.x+fx*d+rx*side*(150+(i%3)*24), wy=state.y+fy*d+ry*side*(150+(i%3)*24);
    const pr=project(wx,wy,0,cam); if(!pr)continue;
    const h=Math.max(3,34*pr.scale), x=pr.x,y=pr.y;
    ctx.globalAlpha=Math.min(.72,.18+pr.scale*.8);ctx.strokeStyle='#3b3d39';ctx.lineWidth=Math.max(1,2*pr.scale);
    ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x,y-h);ctx.stroke();
    if(i%4===0){ctx.fillStyle='#b6a36f';ctx.fillRect(x-5*pr.scale,y-h,10*pr.scale,5*pr.scale)}
  }
  // Deterministic micro-events: a stopped van, cones, or a roadside radio glow. They move with the world seed/time block.
  const kind=Math.floor(hash(t,seed&255,0x811)*3), d=520+hash(t,9,0x812)*850, side=hash(t,10,0x813)>.5?1:-1;
  const wx=state.x+fx*d+rx*side*118, wy=state.y+fy*d+ry*side*118, pr=project(wx,wy,0,cam);
  if(pr){const q=Math.max(.16,pr.scale),x=pr.x,y=pr.y;ctx.globalAlpha=.82;
    if(kind===0){ctx.fillStyle='#514f48';ctx.fillRect(x-20*q,y-15*q,40*q,15*q);ctx.fillStyle='#c4b486';ctx.fillRect(x-14*q,y-23*q,24*q,9*q)}
    else if(kind===1){ctx.fillStyle='#b87445';for(let j=-2;j<=2;j++){ctx.beginPath();ctx.moveTo(x+j*13*q,y);ctx.lineTo(x+j*13*q+5*q,y-17*q);ctx.lineTo(x+j*13*q+10*q,y);ctx.fill()}}
    else {ctx.fillStyle='rgba(224,176,96,.55)';ctx.beginPath();ctx.arc(x,y-10*q,13*q,0,Math.PI*2);ctx.fill();ctx.fillStyle='#343531';ctx.fillRect(x-10*q,y-8*q,20*q,8*q)}
  }
  ctx.restore();
}
'''
if anchor not in s: raise SystemExit('traffic function anchor missing')
s=s.replace(anchor,addition+anchor,1)

# Bind living-road pass after traffic, before film/HUD.
call='drawTraffic(chunks,cam);'
if call not in s: raise SystemExit('traffic call missing')
s=s.replace(call,call+'drawLivingRoad(cam,speed);',1)

# Add restrained suspension/body motion to chase rig for a less sterile mobile-game camera.
needle='rig.fx/=rl;rig.fy/=rl;const cam={'
replacement="rig.fx/=rl;rig.fy/=rl;const roadPulse=Math.sin(state.playSeconds*(5.2+speed*.18))*Math.min(4.5,speed*.22),cam={"
if needle not in s: raise SystemExit('camera rig anchor missing')
s=s.replace(needle,replacement,1)
s=s.replace('height:state.onFoot?100:142+speed*3.8,','height:state.onFoot?100:142+speed*3.8+roadPulse,',1)

p.write_text(s)

bp=Path('android/app/build.gradle'); b=bp.read_text().replace('versionCode 10','versionCode 11').replace("versionName '0.10'","versionName '0.11'"); bp.write_text(b)
print('patched build 0.11 LIVING ROADS',len(s))
