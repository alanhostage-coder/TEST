from pathlib import Path
p=Path('android/app/src/main/assets/www/index.html');s=p.read_text()
s=s.replace('build 0.24 ROAMING DEPTH','build 0.25 OVER THERE').replace('build 0.24 · ROAMING DEPTH','build 0.25 · OVER THERE')
anchor='let pua24Shoulder=0,pua24TrafficPhase=0;'
if anchor not in s: raise SystemExit('0.24 anchor missing')
add=r'''let pua25Turn=0,pua25Branch=0;
function drawOverThere25(){
 const c=ctx.canvas,w=c.width,h=c.height,t=state.playSeconds||0,spd=Math.abs(state.v||0),q=window.__puaQuality||1;
 // Branch choice persists in world-space. Steering toward a junction bends the travelled corridor rather than merely decorating its edge.
 const wish=Math.max(-1,Math.min(1,Math.sin((state.a||0)*1.7)*Math.min(1,spd/6)));
 pua25Turn+=(wish-pua25Turn)*.018;
 if(Math.abs(wish)>.58&&spd>3)pua25Branch+=(wish-pua25Branch)*.006; else pua25Branch*=.9994;
 const branch=Math.max(-.75,Math.min(.75,pua25Branch)),vx=w*(.5+branch*.19),hy=h*.305,base=h*1.02;
 ctx.save();
 // A second traversable-looking corridor peels away and disappears behind estate fabric.
 ctx.globalAlpha=.34*q;ctx.fillStyle='#1d201f';ctx.beginPath();ctx.moveTo(w*.49,hy);ctx.lineTo(vx-w*.22,base);ctx.lineTo(vx+w*.22,base);ctx.lineTo(w*.51,hy);ctx.closePath();ctx.fill();
 const side=branch>=0?1:-1,cell=Math.floor(((state.x||0)*.004+(state.y||0)*.007));
 if((cell%3+3)%3===1){ctx.globalAlpha=.3*q;ctx.fillStyle='#202322';let jy=h*.53,jx=w*(.5+side*.08);ctx.beginPath();ctx.moveTo(jx,jy);ctx.lineTo(jx+side*w*.32,jy+h*.09);ctx.lineTo(jx+side*w*.38,jy+h*.20);ctx.lineTo(jx+side*w*.04,jy+h*.055);ctx.closePath();ctx.fill()}
 // Places to wonder about: lit garage, yard gate and transmitter mast appear by geography, never as objectives.
 const seed=Math.abs(cell*1103515245+12345)%997;
 if(seed%4===0){let x=w*(.17+(seed%61)/100),y=h*.48;ctx.globalAlpha=.48*q;ctx.fillStyle='#292b29';ctx.fillRect(x,y,w*.115,h*.115);ctx.fillStyle='#c98d51';ctx.globalAlpha=.20*q;ctx.fillRect(x+w*.02,y+h*.035,w*.07,h*.05)}
 if(seed%5===0){let x=w*(.74+(seed%13)/100),y=h*.40;ctx.strokeStyle='#252827';ctx.globalAlpha=.42*q;ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(x,y+h*.25);ctx.lineTo(x,y);ctx.stroke();ctx.beginPath();ctx.moveTo(x-w*.035,y+h*.07);ctx.lineTo(x+w*.035,y+h*.07);ctx.stroke()}
 // Radio uncertainty: distance and place gently breathe the existing master output; no station marker tells you why.
 if(window.masterGain&&audioCtx){let fade=.72+.20*(.5+.5*Math.sin(t*.11+cell*.7));masterGain.gain.setTargetAtTime(fade,audioCtx.currentTime,.35)}
 ctx.restore();
}'''
s=s.replace(anchor,anchor+'\n'+add,1)
old='update(dt);draw();drawLivingHorizon23();drawRoamingDepth24();updateHudWithdrawal();requestAnimationFrame(loop)'
new='update(dt);draw();drawLivingHorizon23();drawRoamingDepth24();drawOverThere25();updateHudWithdrawal();requestAnimationFrame(loop)'
if old not in s: raise SystemExit('0.24 loop anchor missing')
s=s.replace(old,new,1)
s=s.replace('Roaming-depth pass: steering-aware chase framing, perspective junction mouths, independent depth-layer traffic, roadside parallax and speed spray make the realm read as a connected place while preserving free roaming and privacy-safe AI EYES.','OVER THERE pass: steering now biases the travelled corridor at junctions, world geography reveals side routes, lit garages, yards and transmitters, and radio reception breathes with place. No markers, missions, scores or identity processing.')
p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 24','versionCode 25').replace("versionName '0.24'","versionName '0.25'");bp.write_text(b)
print('patched build 0.25 OVER THERE',len(s))
