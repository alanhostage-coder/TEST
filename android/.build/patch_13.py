from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()
s=s.replace('build 0.12 WET WORLD','build 0.13 ROAMING FORTH').replace('build 0.12 · WET WORLD','build 0.13 · ROAMING FORTH')

anchor='function drawWetWorld(cam,speed,w){'
addition=r'''function drawRoadKinetics(cam,speed,w){
  const fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx,t=state.playSeconds;
  ctx.save();
  // Persistent power/telegraph lines make speed and Scottish roadside scale legible.
  for(let side=-1;side<=1;side+=2){let last=null;for(let i=0;i<9;i++){
    const d=180+i*230-((t*Math.max(5,speed*8))%230),wx=state.x+fx*d+rx*side*205,wy=state.y+fy*d+ry*side*205,pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.12,pr.scale),top={x:pr.x,y:pr.y-52*q};ctx.globalAlpha=Math.min(.55,.14+q*.7);ctx.strokeStyle='#323733';ctx.lineWidth=Math.max(.7,1.4*q);ctx.beginPath();ctx.moveTo(pr.x,pr.y);ctx.lineTo(top.x,top.y);ctx.stroke();
    if(last){ctx.globalAlpha*=.7;ctx.beginPath();ctx.moveTo(last.x,last.y);ctx.quadraticCurveTo((last.x+top.x)/2,(last.y+top.y)/2+7*q,top.x,top.y);ctx.stroke()}last=top;
  }}
  // Independent roaming vehicles occasionally cross or merge ahead. No objective, reward or trigger.
  const epoch=Math.floor(t/17);for(let j=0;j<2;j++){
    const phase=(t*.055+hash(epoch,j,seed^0xD31))%1,d=460+j*520+hash(epoch,j+7,seed^0xD32)*360,lateral=(phase*2-1)*520;
    const wx=state.x+fx*d+rx*lateral,wy=state.y+fy*d+ry*lateral,pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.14,pr.scale),x=pr.x,y=pr.y;ctx.globalAlpha=.78;ctx.fillStyle=j?'#656963':'#565d60';ctx.fillRect(x-15*q,y-8*q,30*q,9*q);ctx.fillStyle='rgba(205,63,43,.72)';ctx.fillRect(x-13*q,y-7*q,4*q,2*q);ctx.fillRect(x+9*q,y-7*q,4*q,2*q);
    if((w&&w.rain||0)>.18){ctx.globalAlpha=.13;ctx.fillStyle='#d8ddd8';ctx.beginPath();ctx.ellipse(x,y+2*q,32*q,7*q,0,0,Math.PI*2);ctx.fill()}
  }
  // Tyre spray and reflected headlamp fragments appear only with speed + wetness.
  const wet=Math.max(0,(w&&w.rain||0)*.8+(w&&w.cloud||0)*.12);if(speed>2&&wet>.08){ctx.globalAlpha=Math.min(.18,wet*.2);ctx.strokeStyle='#e2e4df';for(let i=0;i<10;i++){const x=W*.5+(hash(i,epoch,seed^0xD33)-.5)*W*.55,y=H*.72+hash(i+20,epoch,seed^0xD34)*H*.24,len=8+speed*1.7;ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+(x-W*.5)*.025,y+len);ctx.stroke()}}
  ctx.restore();
}
'''
if anchor not in s: raise SystemExit('wet world anchor missing')
s=s.replace(anchor,addition+anchor,1)
call='drawWetWorld(cam,speed,w);'
if call not in s: raise SystemExit('wet world call missing')
s=s.replace(call,call+'drawRoadKinetics(cam,speed,w);',1)

# Let speed open the view slightly while keeping the camera weighted behind the car.
needle='focal:Math.min(W,H)*(.50-Math.min(.035,speed*.0018))'
if needle in s:s=s.replace(needle,'focal:Math.min(W,H)*(.50-Math.min(.052,speed*.0024))',1)

p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 12','versionCode 13').replace("versionName '0.12'","versionName '0.13'");bp.write_text(b)
print('patched build 0.13 ROAMING FORTH',len(s))
