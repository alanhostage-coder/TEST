from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()
s=s.replace('build 0.14 JUNCTION LIFE','build 0.15 ESTATE STREETS').replace('build 0.14 · JUNCTION LIFE','build 0.15 · ESTATE STREETS')

anchor='function drawJunctionLife(cam,speed,w){'
addition=r'''function drawEstateStreets(cam,speed,w){
  const fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx,t=state.playSeconds;
  ctx.save();
  // Dense but cheap world-space estate/industrial frontage. Deterministic blocks persist as you drive.
  const travel=t*Math.max(2.5,speed*2.6),base=Math.floor(travel/150);
  for(let i=0;i<13;i++){
    const cell=base+i,d=210+i*145-(travel%145);
    for(const side of [-1,1]){
      const h=hash(cell,side,seed^0xF51),setback=122+h*62;
      const wx=state.x+fx*d+rx*side*setback,wy=state.y+fy*d+ry*side*setback,pr=project(wx,wy,0,cam);if(!pr)continue;
      const q=Math.max(.10,pr.scale),bw=(38+h*34)*q,bh=(18+hash(cell,7,seed^0xF52)*34)*q;
      ctx.globalAlpha=Math.min(.78,.14+q*.72);ctx.fillStyle=h>.72?'#6b655b':h>.38?'#4b504d':'#55534d';ctx.fillRect(pr.x-bw/2,pr.y-bh,bw,bh);
      // garage shutters / sparse lit windows, avoiding neon-game styling
      ctx.globalAlpha*=.75;ctx.fillStyle=h>.55?'rgba(210,183,125,.32)':'rgba(25,28,27,.48)';
      const rows=bh>18?2:1;for(let r=0;r<rows;r++)for(let c=0;c<3;c++)ctx.fillRect(pr.x-bw*.34+c*bw*.25,pr.y-bh*.78+r*bh*.28,Math.max(1,bw*.10),Math.max(1,bh*.08));
      if(h>.80){ctx.globalAlpha=.18;ctx.fillStyle='#b9b8ad';ctx.fillRect(pr.x-side*bw*.55,pr.y-bh*.12,bw*.46,Math.max(1,2*q));}
    }
  }
  // Road-edge posts, bins and barriers give close parallax and readable vehicle speed.
  for(let i=0;i<18;i++){
    const d=95+i*82-((travel*1.35)%82),side=i%2?1:-1,wx=state.x+fx*d+rx*side*(86+(i%3)*8),wy=state.y+fy*d+ry*side*(86+(i%3)*8),pr=project(wx,wy,0,cam);if(!pr)continue;
    const q=Math.max(.1,pr.scale);ctx.globalAlpha=Math.min(.65,.12+q*.65);ctx.fillStyle=i%5===0?'#5d625d':'#77766d';ctx.fillRect(pr.x-2*q,pr.y-10*q,4*q,10*q);
  }
  // A few independent pedestrians are anonymous silhouettes only: no camera, biometrics or identity logic.
  for(let j=0;j<3;j++){
    const epoch=Math.floor(t/23),d=260+((t*(5+j)+hash(epoch,j,seed^0xF53)*800)%980),side=hash(epoch,j,seed^0xF54)>.5?1:-1;
    const wx=state.x+fx*d+rx*side*105,wy=state.y+fy*d+ry*side*105,pr=project(wx,wy,0,cam);if(!pr)continue;const q=Math.max(.1,pr.scale);
    ctx.globalAlpha=Math.min(.5,.12+q*.55);ctx.strokeStyle='#292b2a';ctx.lineWidth=Math.max(1,2*q);ctx.beginPath();ctx.moveTo(pr.x,pr.y-11*q);ctx.lineTo(pr.x,pr.y-4*q);ctx.lineTo(pr.x-3*q,pr.y);ctx.moveTo(pr.x,pr.y-4*q);ctx.lineTo(pr.x+3*q,pr.y);ctx.stroke();ctx.beginPath();ctx.arc(pr.x,pr.y-14*q,2.4*q,0,Math.PI*2);ctx.fillStyle='#343532';ctx.fill();
  }
  ctx.restore();
}
'''
if anchor not in s: raise SystemExit('junction life anchor missing')
s=s.replace(anchor,addition+anchor,1)
call='drawJunctionLife(cam,speed,w);'
if call not in s: raise SystemExit('junction life call missing')
s=s.replace(call,call+'drawEstateStreets(cam,speed,w);',1)

p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 14','versionCode 15').replace("versionName '0.14'","versionName '0.15'");bp.write_text(b)
print('patched build 0.15 ESTATE STREETS',len(s))
