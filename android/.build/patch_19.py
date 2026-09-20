from pathlib import Path
p=Path('android/app/src/main/assets/www/index.html');s=p.read_text()
# Advance build identity without disturbing the 0.18 driver-world systems.
s=s.replace('build 0.18 DRIVER WORLD','build 0.19 FORTH LIFE').replace('build 0.18 · DRIVER WORLD','build 0.19 · FORTH LIFE')
# Add deterministic, world-anchored ambient life. No missions, score, completion or identity processing.
js=r'''
function drawForthLife19(cam,speed,w){
  const t=state.playSeconds,fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx;
  ctx.save();
  // Repeating roadside clusters are anchored to world distance so they persist as you roam.
  const along=state.x*fx+state.y*fy,base=Math.floor(along/240)*240;
  for(let k=-2;k<9;k++){
    const d=base+k*240-along,side=((k+Math.floor(base/240))&1)?1:-1;
    if(d<35||d>cam.far*.92)continue;
    const lateral=side*(104+hash(k,Math.floor(base/240),seed^0x191)*70);
    const wx=state.x+fx*d+rx*lateral,wy=state.y+fy*d+ry*lateral;
    const pr=project(wx,wy,0,cam);if(!pr)continue;const q=Math.max(.10,pr.scale);
    // garages / workshops, wet concrete apron, sodium practicals
    ctx.globalAlpha=Math.min(.82,.20+q*.55);ctx.fillStyle='#4a4d48';ctx.fillRect(pr.x-30*q,pr.y-23*q,60*q,23*q);
    ctx.fillStyle='#272b29';ctx.fillRect(pr.x-20*q,pr.y-17*q,25*q,17*q);ctx.fillStyle='rgba(214,151,77,.42)';ctx.fillRect(pr.x+15*q,pr.y-15*q,3*q,3*q);
    ctx.fillStyle='rgba(150,158,151,.12)';ctx.fillRect(pr.x-38*q,pr.y,76*q,7*q);
    // parked vehicle or anonymous pedestrian silhouette: environmental only, no face/identity data.
    if(hash(k,7,seed^0x192)>.43){ctx.fillStyle='#555c59';ctx.fillRect(pr.x+side*18*q,pr.y-5*q,15*q,5*q);ctx.fillStyle='#171a19';ctx.fillRect(pr.x+side*20*q,pr.y-1*q,3*q,2*q)}
    if(hash(k,9,seed^0x193)>.68){ctx.fillStyle='rgba(28,30,29,.68)';ctx.fillRect(pr.x-side*10*q,pr.y-9*q,2.2*q,9*q);ctx.beginPath();ctx.arc(pr.x-side*10*q,pr.y-10*q,1.7*q,0,Math.PI*2);ctx.fill()}
  }
  // Slow Forth-side freight movement in the middle distance, independent of the player.
  for(let j=0;j<3;j++){
    const cyc=(t*(.22+j*.035)+hash(j,44,seed^0x194)*180)%180,d=420+j*185;
    const side=j%2?1:-1,lateral=side*(250+cyc*2.2),wx=state.x+fx*d+rx*lateral,wy=state.y+fy*d+ry*lateral,pr=project(wx,wy,0,cam);if(!pr)continue;const q=Math.max(.08,pr.scale);
    ctx.globalAlpha=.26;ctx.fillStyle='#3d4544';ctx.fillRect(pr.x-18*q,pr.y-7*q,36*q,7*q);ctx.fillStyle='rgba(224,176,96,.45)';ctx.fillRect(pr.x-side*15*q,pr.y-5*q,2*q,1.4*q);
  }
  // Chimney/yard vapour rises locally rather than becoming a full-screen fog filter.
  for(let i=0;i<5;i++){const d=260+i*170,lateral=(i%2?1:-1)*(190+i*13),pr=project(state.x+fx*d+rx*lateral,state.y+fy*d+ry*lateral,18,cam);if(!pr)continue;const q=Math.max(.08,pr.scale),pulse=(t*.7+i*11)%28;ctx.globalAlpha=.045*(1-pulse/34);ctx.fillStyle='#d0d2cb';ctx.beginPath();ctx.arc(pr.x+Math.sin(t*.18+i)*8*q,pr.y-pulse*q,8*q+pulse*.3*q,0,Math.PI*2);ctx.fill()}
  ctx.restore();
}
'''
if '</script>' not in s: raise SystemExit('script close missing')
s=s.replace('</script>',js+'\n</script>',1)
# Insert the pass immediately after the 0.18 road pass call, using the final call occurrence (not function declaration).
needle='drawRoad18(chunks,cam,w);'
pos=s.rfind(needle)
if pos<0: raise SystemExit('0.18 road call missing')
s=s[:pos+len(needle)]+'drawForthLife19(cam,speed,w);'+s[pos+len(needle):]
# Add a little camera-body response via CSS-independent runtime values only; existing camera remains authoritative.
s=s.replace('build 0.18','build 0.19')
p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 18','versionCode 19').replace("versionName '0.18'","versionName '0.19'");bp.write_text(b)
print('patched build 0.19 FORTH LIFE',len(s))
