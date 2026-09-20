from pathlib import Path
p=Path('android/app/src/main/assets/www/index.html');s=p.read_text()
s=s.replace('build 0.22 BOOT RESCUE','build 0.23 LIVING HORIZON').replace('build 0.22 · BOOT RESCUE','build 0.23 · LIVING HORIZON')
anchor="let perfAvg=.016;window.__puaQuality=1;"
if anchor not in s: raise SystemExit('performance anchor missing')
add=r'''let pua23Cam=0,pua23Pulse=0;
function drawLivingHorizon23(){
 const c=ctx.canvas,w=c.width,h=c.height,t=state.playSeconds||0,spd=Math.abs(state.v||0),q=window.__puaQuality||1;
 pua23Cam+=(Math.sin((state.a||0)*1.7+t*.09)*Math.min(1,spd/13)-pua23Cam)*.035;
 pua23Pulse=(pua23Pulse+.0025+spd*.00005)%1;
 ctx.save();
 // distant Forth-side life: original procedural silhouettes, softened by haar
 const hy=h*.305, drift=((state.x||0)*.013+(state.y||0)*.009)%180;
 ctx.globalAlpha=.16*q;ctx.fillStyle='#1a2020';
 for(let i=-2;i<9;i++){let x=i*w*.15-drift,hh=h*(.025+((i*37+11)%5)*.009);ctx.fillRect(x,hy-hh,w*.09,hh);if(i%3===0){ctx.fillRect(x+w*.025,hy-hh-h*.055,w*.008,h*.055);ctx.fillRect(x+w*.033,hy-hh-h*.052,w*.045,h*.005)}}
 // moving freight/service lights on the far shore make the realm continue without the player
 ctx.globalAlpha=.30;for(let i=0;i<3;i++){let x=((t*(7+i*2)+i*w*.31+drift)% (w*1.25))-w*.12;ctx.fillStyle=i===1?'#d39a5c':'#c9b07a';ctx.fillRect(x,hy-h*.006,Math.max(2,w*.004),Math.max(2,h*.003))}
 // wet-road depth glints converge toward the chase-camera vanishing point
 const vx=w*(.5+pua23Cam*.055),base=h*.91;ctx.globalAlpha=.10;ctx.strokeStyle='#d8c4a0';ctx.lineWidth=1;
 for(let i=0;i<7;i++){let z=((pua23Pulse+i/7)%1),y=hy+(base-hy)*z*z,x=vx+(i%2?1:-1)*w*(.035+.25*z);ctx.beginPath();ctx.moveTo(vx,hy);ctx.lineTo(x,y);ctx.stroke()}
 // occasional anonymous roadside activity, no faces/identity/biometrics
 if(((Math.floor((state.x||0)/420)+Math.floor((state.y||0)/420))&3)===1){ctx.globalAlpha=.28*q;ctx.fillStyle='#272724';let side=((Math.floor((state.x||0)/190)&1)?1:-1);for(let i=0;i<2;i++){let y=h*(.60+i*.075),sc=.45+i*.25,x=w*.5+side*w*(.22+i*.07);ctx.fillRect(x,y-h*.035*sc,w*.009*sc,h*.035*sc);ctx.beginPath();ctx.arc(x+w*.0045*sc,y-h*.041*sc,w*.005*sc,0,Math.PI*2);ctx.fill()}}
 // haar bands move independently of screen, preserving photographic atmosphere without a colour wash
 ctx.globalAlpha=.035+.025*Math.sin(t*.021);ctx.fillStyle='#d7d8d1';for(let i=0;i<3;i++){let yy=hy+h*(.035*i)+Math.sin(t*.017+i*2.1)*h*.012;ctx.fillRect(0,yy,w,h*.022)}
 ctx.restore();
}'''
s=s.replace(anchor,add+'\n'+anchor,1)
old="update(dt);draw();updateHudWithdrawal();requestAnimationFrame(loop)"
new="update(dt);draw();drawLivingHorizon23();updateHudWithdrawal();requestAnimationFrame(loop)"
if old not in s: raise SystemExit('loop draw anchor missing')
s=s.replace(old,new,1)
s=s.replace('Boot-rescue pass: the migration that could execute before the road system existed has been moved behind road initialisation, and Proceed no longer depends on audio starting successfully.','Living-horizon pass: distant Forth industry, independent service movement, wet-road convergence cues, anonymous roadside life and world-space haar add depth and persistence without missions, scores or identity processing.')
p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 22','versionCode 23').replace("versionName '0.22'","versionName '0.23'");bp.write_text(b)
print('patched build 0.23 LIVING HORIZON',len(s))
