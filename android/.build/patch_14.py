from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()
s=s.replace('build 0.13 ROAMING FORTH','build 0.14 JUNCTION LIFE').replace('build 0.13 · ROAMING FORTH','build 0.14 · JUNCTION LIFE')

anchor='function drawRoadKinetics(cam,speed,w){'
addition=r'''function drawJunctionLife(cam,speed,w){
  const fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx,t=state.playSeconds;
  ctx.save();
  // Side-road mouths create readable choices and stop the world feeling like one endless corridor.
  for(let i=0;i<5;i++){
    const slot=Math.floor((t*5+i*311)/19),d=330+i*410-((t*Math.max(3,speed*3.2))%410),side=hash(slot,i,seed^0xE41)>.5?1:-1;
    const wx=state.x+fx*d+rx*side*128,wy=state.y+fy*d+ry*side*128,pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.12,pr.scale),reach=110*q;
    ctx.globalAlpha=Math.min(.38,.10+q*.48);ctx.fillStyle='#303431';ctx.beginPath();ctx.moveTo(pr.x-18*q,pr.y);ctx.lineTo(pr.x+18*q,pr.y);ctx.lineTo(pr.x+side*reach,pr.y+22*q);ctx.lineTo(pr.x+side*reach,pr.y+38*q);ctx.closePath();ctx.fill();
    ctx.globalAlpha*=.7;ctx.strokeStyle='rgba(210,207,190,.45)';ctx.lineWidth=Math.max(.6,q);ctx.beginPath();ctx.moveTo(pr.x+side*10*q,pr.y+4*q);ctx.lineTo(pr.x+side*reach*.85,pr.y+28*q);ctx.stroke();
  }
  // Opposing traffic gets independent lane drift, scale and lights: ambient road life, never a mission.
  const epoch=Math.floor(t/11);for(let j=0;j<4;j++){
    const travel=(t*(22+j*3)+hash(epoch,j,seed^0xE42)*700)%1450,d=170+travel,lane=(j%2?1:-1)*(46+hash(j,epoch,seed^0xE43)*22);
    const wx=state.x+fx*d+rx*lane,wy=state.y+fy*d+ry*lane,pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.11,pr.scale),ww=24*q,hh=8*q;ctx.globalAlpha=Math.min(.82,.2+q);ctx.fillStyle=j%3?'#444a49':'#6a6258';ctx.fillRect(pr.x-ww/2,pr.y-hh,ww,hh);
    ctx.fillStyle='rgba(242,225,171,.72)';ctx.fillRect(pr.x-ww*.36,pr.y-hh*.78,ww*.16,Math.max(1,q*1.5));ctx.fillRect(pr.x+ww*.20,pr.y-hh*.78,ww*.16,Math.max(1,q*1.5));
  }
  // Low mist pockets sit in world depth instead of a screen-wide filter.
  const damp=Math.max(0,(w&&w.rain||0)*.45+(w&&w.cloud||0)*.22);if(damp>.08){for(let k=0;k<4;k++){const d=500+k*360,wx=state.x+fx*d+rx*(hash(k,epoch,seed^0xE44)-.5)*420,wy=state.y+fy*d+ry*(hash(k,epoch,seed^0xE45)-.5)*420,pr=project(wx,wy,0,cam);if(!pr)continue;const q=Math.max(.15,pr.scale);ctx.globalAlpha=Math.min(.09,damp*.11);ctx.fillStyle='#d8d9d2';ctx.beginPath();ctx.ellipse(pr.x,pr.y,150*q,20*q,0,0,Math.PI*2);ctx.fill()}}
  ctx.restore();
}
'''
if anchor not in s: raise SystemExit('road kinetics anchor missing')
s=s.replace(anchor,addition+anchor,1)
call='drawRoadKinetics(cam,speed,w);'
if call not in s: raise SystemExit('road kinetics call missing')
s=s.replace(call,call+'drawJunctionLife(cam,speed,w);',1)

# More authoritative high-speed chase framing without destabilising low-speed steering.
needle='focal:Math.min(W,H)*(.50-Math.min(.052,speed*.0024))'
if needle in s:s=s.replace(needle,'focal:Math.min(W,H)*(.505-Math.min(.060,speed*.0027))',1)

p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 13','versionCode 14').replace("versionName '0.13'","versionName '0.14'");bp.write_text(b)
print('patched build 0.14 JUNCTION LIFE',len(s))
