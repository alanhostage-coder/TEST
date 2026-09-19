from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()
s=s.replace('build 0.11 LIVING ROADS','build 0.12 WET WORLD').replace('build 0.11 · LIVING ROADS','build 0.12 · WET WORLD')

# Add wet-road light behaviour, lane-scale cues and persistent Forth-side landmark silhouettes.
anchor='function drawLivingRoad(cam,speed){'
addition=r'''function drawWetWorld(cam,speed,w){
  const fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx;
  ctx.save();
  // Wet tarmac catches broken sky/sodium reflections instead of a flat filter.
  const wet=Math.max(.08,Math.min(.72,(w&&w.rain||0)*.72+(w&&w.cloud||0)*.18));
  ctx.globalAlpha=wet*.34;
  for(let i=0;i<14;i++){
    const d=110+i*175-((state.playSeconds*Math.max(5,speed*9))%175);if(d<cam.near)continue;
    const side=(i%2?-.36:.36),wx=state.x+fx*d+rx*side*120,wy=state.y+fy*d+ry*side*120,pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.12,pr.scale),len=Math.max(2,28*q);
    ctx.strokeStyle=i%3===0?'rgba(220,166,91,.42)':'rgba(201,210,204,.25)';ctx.lineWidth=Math.max(1,5*q);
    ctx.beginPath();ctx.moveTo(pr.x,pr.y);ctx.lineTo(pr.x,pr.y+len);ctx.stroke();
  }
  // Distant persistent landmarks: sheds, gantry/crane forms and stacks tied to world cells.
  const cell=Math.floor((state.x+state.y)*.00032);
  for(let i=0;i<7;i++){
    const d=1050+i*290+hash(cell,i,seed^0x923)*420,side=(hash(cell,i+17,seed^0x924)-.5)*2;
    const wx=state.x+fx*d+rx*side*(430+i*34),wy=state.y+fy*d+ry*side*(430+i*34),pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.1,pr.scale),x=pr.x,y=pr.y,h=(70+hash(cell,i+30,seed^0x925)*120)*q;
    ctx.globalAlpha=.28;ctx.strokeStyle='#303735';ctx.lineWidth=Math.max(1,3*q);ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x,y-h);ctx.lineTo(x+45*q,y-h+18*q);ctx.stroke();
    if(i%3===0){ctx.fillStyle='rgba(202,157,82,.35)';ctx.fillRect(x-2*q,y-h-3*q,5*q,5*q)}
  }
  // Haar bands move slowly across the view and thicken toward the Forth horizon.
  ctx.globalAlpha=.045+.08*(w&&w.cloud||0);ctx.fillStyle='#d9d8ce';
  const drift=(state.playSeconds*3)%180;for(let i=0;i<4;i++)ctx.fillRect(-90+((i*270+drift)%(W+180)),cam.horizon-22+i*11,190,10+i*3);
  ctx.restore();
}
'''
if anchor not in s: raise SystemExit('living road anchor missing')
s=s.replace(anchor,addition+anchor,1)

# Run the world-depth pass after road life and before film/HUD.
call='drawLivingRoad(cam,speed);'
if call not in s: raise SystemExit('living road call missing')
s=s.replace(call,call+'drawWetWorld(cam,speed,w);',1)

# Give steering a small look-ahead bias so bends reveal themselves rather than camera-locking to the boot lid.
needle='rig.fx+=(fx-rig.fx)*.09;rig.fy+=(fy-rig.fy)*.09;'
replacement='const lookA=state.a+(state.steer||0)*Math.min(.16,.035+speed*.004),lookFx=Math.cos(lookA),lookFy=Math.sin(lookA);rig.fx+=(lookFx-rig.fx)*.09;rig.fy+=(lookFy-rig.fy)*.09;'
if needle not in s: raise SystemExit('chase look anchor missing')
s=s.replace(needle,replacement,1)

p.write_text(s)

bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 11','versionCode 12').replace("versionName '0.11'","versionName '0.12'");bp.write_text(b)
print('patched build 0.12 WET WORLD',len(s))
