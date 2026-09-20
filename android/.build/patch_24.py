from pathlib import Path
p=Path('android/app/src/main/assets/www/index.html');s=p.read_text()
s=s.replace('build 0.23 LIVING HORIZON','build 0.24 ROAMING DEPTH').replace('build 0.23 · LIVING HORIZON','build 0.24 · ROAMING DEPTH')
anchor='let pua23Cam=0,pua23Pulse=0;'
if anchor not in s: raise SystemExit('0.23 camera anchor missing')
add=r'''let pua24Shoulder=0,pua24TrafficPhase=0;
function drawRoamingDepth24(){
 const c=ctx.canvas,w=c.width,h=c.height,t=state.playSeconds||0,spd=Math.abs(state.v||0),q=window.__puaQuality||1;
 // Chase-camera shoulder follows steering slowly, giving bends a readable third-person reveal.
 const steer=Math.sin((state.a||0)*1.25+t*.055)*Math.min(1,spd/10);
 pua24Shoulder+=(steer-pua24Shoulder)*.028;
 pua24TrafficPhase=(pua24TrafficPhase+(.0018+spd*.000035))%1;
 const vx=w*(.5+pua24Shoulder*.072),hy=h*.31,roadBase=h*.98;
 ctx.save();
 // World-anchored side roads: broad perspective mouths make the realm feel traversable beyond one corridor.
 const cell=Math.floor(((state.x||0)*.006+(state.y||0)*.004));
 ctx.globalAlpha=.22*q;ctx.fillStyle='#202322';
 for(let j=0;j<2;j++){let z=.42+j*.27,y=hy+(roadBase-hy)*z*z,side=((cell+j)&1)?1:-1;let edge=vx+side*w*(.12+.24*z);ctx.beginPath();ctx.moveTo(vx+side*w*.035,y-h*.018);ctx.lineTo(edge,y-h*.045);ctx.lineTo(edge+side*w*.19,y+h*.075);ctx.lineTo(vx+side*w*.07,y+h*.028);ctx.closePath();ctx.fill()}
 // Independent traffic occupies depth layers and crosses junction space without player triggers.
 for(let i=0;i<5;i++){let z=(pua24TrafficPhase+i*.193)%1,y=hy+(roadBase-hy)*z*z,sc=.18+z*.82,lane=(i&1?-.075:.075),x=vx+w*lane*z+Math.sin(t*.17+i*3.1)*w*.006*z;ctx.globalAlpha=(.12+.38*z)*q;ctx.fillStyle=i&1?'#303332':'#252827';ctx.fillRect(x-w*.018*sc,y-h*.018*sc,w*.036*sc,h*.022*sc);ctx.fillStyle=i&1?'#b88d62':'#d5c18d';ctx.fillRect(x-w*.014*sc,y-h*.002*sc,w*.006*sc,h*.004*sc);ctx.fillRect(x+w*.008*sc,y-h*.002*sc,w*.006*sc,h*.004*sc)}
 // Near-field poles, fencing and verge markers strengthen parallax and physical scale.
 ctx.strokeStyle='#171a19';ctx.lineWidth=Math.max(1,w*.0015);for(let i=0;i<6;i++){let z=.30+i*.12,y=hy+(roadBase-hy)*z*z,side=(i&1)?1:-1,x=vx+side*w*(.18+.29*z);ctx.globalAlpha=(.08+.22*z)*q;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x,y-h*(.055+.09*z));ctx.stroke();if(i<5){ctx.beginPath();ctx.moveTo(x,y-h*(.04+.075*z));ctx.lineTo(x+side*w*.08,y-h*(.025+.055*z));ctx.stroke()}}
 // Fine road spray at speed, spatially tied to lower road plane rather than a screen filter.
 if(spd>7){ctx.strokeStyle='#d7d8d1';ctx.lineWidth=1;ctx.globalAlpha=Math.min(.11,(spd-7)*.007)*q;for(let i=0;i<10;i++){let r=((i*47+Math.floor(t*19))%101)/101,x=vx+(r-.5)*w*.38,y=h*(.78+((i*29)%19)/100);ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x-pua24Shoulder*w*.012,y-h*.018);ctx.stroke()}}
 ctx.restore();
}'''
s=s.replace(anchor,anchor+'\n'+add,1)
old='update(dt);draw();drawLivingHorizon23();updateHudWithdrawal();requestAnimationFrame(loop)'
new='update(dt);draw();drawLivingHorizon23();drawRoamingDepth24();updateHudWithdrawal();requestAnimationFrame(loop)'
if old not in s: raise SystemExit('0.23 loop anchor missing')
s=s.replace(old,new,1)
s=s.replace('Living-horizon pass: distant Forth industry, independent service movement, wet-road convergence cues, anonymous roadside life and world-space haar add depth and persistence without missions, scores or identity processing.','Roaming-depth pass: steering-aware chase framing, perspective junction mouths, independent depth-layer traffic, roadside parallax and speed spray make the realm read as a connected place while preserving free roaming and privacy-safe AI EYES.')
p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 23','versionCode 24').replace("versionName '0.23'","versionName '0.24'");bp.write_text(b)
print('patched build 0.24 ROAMING DEPTH',len(s))
