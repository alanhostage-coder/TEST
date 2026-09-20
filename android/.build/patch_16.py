from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()
s=s.replace('build 0.15 ESTATE STREETS','build 0.16 FORTH WEATHER').replace('build 0.15 · ESTATE STREETS','build 0.16 · FORTH WEATHER')

anchor='function drawEstateStreets(cam,speed,w){'
addition=r'''function drawForthWeather(cam,speed,w){
  const t=state.playSeconds, phase=(t%240)/240, pulse=.5+.5*Math.sin(t*.021), horizon=w*.50;
  ctx.save();
  // Slow world weather: haar banks arrive in broad fronts instead of a flat overlay.
  const front=(phase<.5?phase*2:(1-phase)*2);
  for(let i=0;i<5;i++){
    const drift=((t*(2+i*.35)+i*w*.31)%(w*1.45))-w*.22;
    const ww=w*(.24+i*.055), hh=w*(.018+i*.006);
    const g=ctx.createRadialGradient(drift,horizon-i*9,2,drift,horizon-i*9,ww*.55);
    g.addColorStop(0,'rgba(205,207,198,'+(0.025+front*.035)+')');g.addColorStop(1,'rgba(205,207,198,0)');
    ctx.fillStyle=g;ctx.fillRect(drift-ww*.6,horizon-hh*3,ww*1.2,hh*6);
  }
  // Low winter sun occasionally breaks through cloud; warm memory comes from light, never a pink filter.
  const sun=Math.max(0,Math.sin((phase-.08)*Math.PI*2))*.18;
  if(sun>.01){const sx=w*(.18+phase*.42),sy=w*.17;const rg=ctx.createRadialGradient(sx,sy,1,sx,sy,w*.18);rg.addColorStop(0,'rgba(244,190,116,'+sun+')');rg.addColorStop(.18,'rgba(220,155,101,'+(sun*.42)+')');rg.addColorStop(1,'rgba(160,120,100,0)');ctx.fillStyle=rg;ctx.fillRect(0,0,w,w*.55);}
  // Wind-blown road grit/rain catches headlights at speed. Sparse, directional, cheap on Android.
  const density=Math.floor(10+Math.min(18,speed*.12));ctx.strokeStyle='rgba(218,220,211,.16)';ctx.lineWidth=1;
  for(let i=0;i<density;i++){const h=hash(Math.floor(t*3),i,seed^0xF61),x=(h*w+t*(24+i%4)*speed*.025)%w,y=horizon+hash(i,17,seed^0xF62)*(w-horizon);const len=3+speed*.035;ctx.globalAlpha=.05+front*.12;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x-2-len*.25,y+len);ctx.stroke();}
  // Independent service traffic on distant side roads: vans pause, turn and disappear without player triggers.
  for(let j=0;j<3;j++){const cycle=(t*(.65+j*.11)+hash(j,33,seed^0xF63)*71)%95,d=310+j*210+cycle*5,side=j%2?1:-1;const fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx,turn=Math.sin(cycle*.065)*42;const wx=state.x+fx*d+rx*(side*(118+turn)),wy=state.y+fy*d+ry*(side*(118+turn)),pr=project(wx,wy,0,cam);if(!pr)continue;const q=Math.max(.09,pr.scale);ctx.globalAlpha=Math.min(.55,.12+q*.5);ctx.fillStyle=j===1?'#676b67':'#4e5453';ctx.fillRect(pr.x-7*q,pr.y-6*q,14*q,6*q);ctx.fillStyle='rgba(218,177,103,.42)';ctx.fillRect(pr.x-side*6*q,pr.y-4*q,2*q,1.5*q);}
  ctx.restore();
}
'''
if anchor not in s: raise SystemExit('estate streets anchor missing')
s=s.replace(anchor,addition+anchor,1)
call='drawEstateStreets(cam,speed,w);'
if call not in s: raise SystemExit('estate streets call missing')
s=s.replace(call,call+'drawForthWeather(cam,speed,w);',1)
p.write_text(s)

bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 15','versionCode 16').replace("versionName '0.15'","versionName '0.16'");bp.write_text(b)
print('patched build 0.16 FORTH WEATHER',len(s))
