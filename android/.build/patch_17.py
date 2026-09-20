from pathlib import Path

p=Path('android/app/src/main/assets/www/index.html')
s=p.read_text()

s=s.replace('build 0.16 FORTH WEATHER','build 0.17 CONTROL RESET').replace('build 0.16 · FORTH WEATHER','build 0.17 · CONTROL RESET')

# 1) Runtime repair: world passes 0.11–0.16 call project(), but 0.9 renamed
# the projection primitive to worldToScreen(). Restore the shared helper and z lift.
anchor="function worldToScreen(x,y,cam){const dx=x-cam.x,dy=y-cam.y;const side=dx*(-cam.fy)+dy*cam.fx;const depth=dx*cam.fx+dy*cam.fy;if(depth<cam.near||depth>cam.far)return {x:-9999,y:-9999,depth,scale:0,visible:false};const scale=cam.focal/depth;return {x:W*.5+side*scale,y:cam.horizon+cam.height*scale,depth,scale,visible:true}}"
project=anchor+"\nfunction project(x,y,z,cam){const p=worldToScreen(x,y,cam);if(!p.visible)return null;return {x:p.x,y:p.y-(z||0)*p.scale,depth:p.depth,scale:p.scale,visible:true}}"
if anchor not in s: raise SystemExit('worldToScreen anchor missing')
s=s.replace(anchor,project,1)

# 2) Forth weather used the weather object as if it were viewport width, poisoning
# the canvas with NaN geometry. Replace it with an actual screen-space weather pass.
start=s.find('function drawForthWeather(cam,speed,w){')
end=s.find('\nfunction drawEstateStreets(cam,speed,w){',start)
if start<0 or end<0: raise SystemExit('Forth weather function anchor missing')
weather=r'''function drawForthWeather(cam,speed,w){
  const t=state.playSeconds,phase=(t%260)/260,front=phase<.5?phase*2:(1-phase)*2;
  const damp=Math.max(0,Math.min(1,(w&&w.rain?0.72:0)+(w&&w.cloud||0)*.34));
  ctx.save();
  // Haar lives around the horizon, not across the entire game as a filter.
  for(let i=0;i<4;i++){
    const drift=((t*(1.2+i*.23)+i*W*.29)%(W*1.5))-W*.25,ww=W*(.24+i*.07),hh=H*(.025+i*.008);
    const g=ctx.createRadialGradient(drift,cam.horizon-i*7,3,drift,cam.horizon-i*7,ww*.55);
    g.addColorStop(0,'rgba(205,209,202,'+(0.02+front*.035+damp*.025)+')');g.addColorStop(1,'rgba(205,209,202,0)');
    ctx.fillStyle=g;ctx.fillRect(drift-ww*.62,cam.horizon-hh*3,ww*1.24,hh*6);
  }
  const sun=Math.max(0,Math.sin((phase-.10)*Math.PI*2))*(.10*(1-damp));
  if(sun>.005){const sx=W*(.16+phase*.48),sy=Math.max(28,cam.horizon*.46),rg=ctx.createRadialGradient(sx,sy,2,sx,sy,W*.16);rg.addColorStop(0,'rgba(239,186,113,'+sun+')');rg.addColorStop(.24,'rgba(215,154,96,'+(sun*.34)+')');rg.addColorStop(1,'rgba(160,120,100,0)');ctx.fillStyle=rg;ctx.fillRect(0,0,W,cam.horizon+40)}
  if(damp>.12&&speed>.6){const density=Math.floor(8+Math.min(20,speed*1.5));ctx.strokeStyle='rgba(218,222,216,.17)';ctx.lineWidth=1;for(let i=0;i<density;i++){const h=hash(Math.floor(t*4),i,seed^0xF61),x=(h*W+t*(19+i%5)*speed)%W,y=cam.horizon+hash(i,17,seed^0xF62)*(H-cam.horizon),len=4+speed*.85;ctx.globalAlpha=.035+damp*.12;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x-2-len*.18,y+len);ctx.stroke()}}
  // Independent service vans remain ambient road life.
  for(let j=0;j<3;j++){const cycle=(t*(.65+j*.11)+hash(j,33,seed^0xF63)*71)%95,d=310+j*210+cycle*5,side=j%2?1:-1,fx=cam.fx,fy=cam.fy,rx=-fy,ry=fx,turn=Math.sin(cycle*.065)*42,wx=state.x+fx*d+rx*(side*(118+turn)),wy=state.y+fy*d+ry*(side*(118+turn)),pr=project(wx,wy,0,cam);if(!pr)continue;const q=Math.max(.09,pr.scale);ctx.globalAlpha=Math.min(.55,.12+q*.5);ctx.fillStyle=j===1?'#676b67':'#4e5453';ctx.fillRect(pr.x-7*q,pr.y-6*q,14*q,6*q);ctx.fillStyle='rgba(218,177,103,.42)';ctx.fillRect(pr.x-side*6*q,pr.y-4*q,2*q,1.5*q)}
  ctx.restore();
}'''
s=s[:start]+weather+s[end:]

# 3) Remove the giant projected 900x900 chunk rectangles that read as square lakes.
old=" const chunks=chunksAround(state.x,state.y,viewChunks);for(const c of chunks){const n=noise(c.cx*CH+450,c.cy*CH+450,2100),col=n<.23?'#536f73':n>.76?'#6e705e':'#777b68';fillWorldRect(c.cx*CH,c.cy*CH,CH+2,CH+2,col,cam)}"
new=""" const chunks=chunksAround(state.x,state.y,viewChunks);ctx.save();const ground=ctx.createLinearGradient(0,cam.horizon,0,H);ground.addColorStop(0,'#59605a');ground.addColorStop(.42,'#484e49');ground.addColorStop(1,'#343936');ctx.fillStyle=ground;ctx.fillRect(0,cam.horizon,W,H-cam.horizon);ctx.globalAlpha=.07;ctx.fillStyle='#d7d1bd';for(let i=0;i<10;i++){const y=cam.horizon+18+i*(H-cam.horizon)/10;ctx.fillRect(0,y,W,1)}ctx.restore()"""
if old not in s: raise SystemExit('chunk terrain draw anchor missing')
s=s.replace(old,new,1)

# 4) Road colour + markings. The old road was nearly black with a single yellow cord.
s=s.replace("line(r.x1,r.y1,r.x2,r.y2,r.w+18,'#414442',cam);line(r.x1,r.y1,r.x2,r.y2,r.w,'#262a29',cam);line(r.x1,r.y1,r.x2,r.y2,2,'rgba(226,210,159,.34)',cam)",
            "line(r.x1,r.y1,r.x2,r.y2,r.w+16,'#555a55',cam);line(r.x1,r.y1,r.x2,r.y2,r.w,'#303432',cam);line(r.x1,r.y1,r.x2,r.y2,1.2,'rgba(225,218,193,.28)',cam)",1)

# 5) Camera look-ahead had no live steer value. Keep the analogue axis in state.
needle="steer=thumbAxes.active?thumbAxes.x:((left?-1:0)+(right?1:0));const grip="
if needle not in s: raise SystemExit('steer update anchor missing')
s=s.replace(needle,"steer=thumbAxes.active?thumbAxes.x:((left?-1:0)+(right?1:0));state.steer=steer;const grip=",1)

# 6) Mobile UI reset: keep one thumb, IN/OUT, EYES and MORE. Everything else moves
# behind MORE; make status/log peripheral instead of covering half the road.
css=r'''
  /* 0.17 CONTROL RESET */
  @media (hover:none) and (pointer:coarse){
    #thumbDock{left:max(10px,env(safe-area-inset-left));bottom:max(10px,env(safe-area-inset-bottom));width:238px;height:156px;transform:none!important}
    #thumbBase{left:4px;bottom:4px;width:96px;height:96px;border-color:rgba(255,255,255,.18);background:radial-gradient(circle at 43% 36%,rgba(255,255,255,.07),rgba(0,0,0,.42) 72%)}
    #thumbKnob{left:30px;top:30px;width:36px;height:36px;border-color:rgba(255,255,255,.30)}
    #thumbHint{display:none}
    .thumbAction{width:42px;height:42px;font-size:7px!important;opacity:.62!important;background:rgba(5,7,6,.46)!important}
    .a-context{left:108px;bottom:4px}.a-eyes{left:148px;bottom:44px}.a-more{left:188px;bottom:4px}
    .a-mark,.a-relay,.a-fmminus,.a-fmplus{display:none!important}
    #thumbMoreMenu{left:104px;bottom:52px;width:142px;grid-template-columns:repeat(2,64px);gap:5px;padding:6px;border-radius:14px;background:rgba(5,7,6,.82)}
    #thumbMoreMenu.show{display:grid}.thumbMini{width:64px;height:30px;font-size:7px!important}
    #left{left:auto;right:10px;top:10px;width:auto;max-width:230px;padding:7px 9px;background:rgba(7,9,8,.23);border-color:rgba(255,255,255,.07);backdrop-filter:blur(3px)}
    #place{font-size:12px;letter-spacing:.10em}#meta,#status{display:none}#radio{font-size:9px;margin-top:3px;opacity:.74}
    #log{left:auto;right:10px;bottom:10px;width:min(36vw,360px);min-height:0;padding:8px 10px;font-size:10px;line-height:1.35;background:rgba(7,9,8,.30);border-color:rgba(255,255,255,.07)}
  }
'''
if '</style>' not in s: raise SystemExit('style close missing')
s=s.replace('</style>',css+'\n</style>',1)

# Move secondary actions into MORE without changing the existing event system.
menu_anchor='      <button class="thumbMini" data-action="s">SHARE</button>\n'
if menu_anchor not in s: raise SystemExit('more menu anchor missing')
menu_extra=menu_anchor+'      <button class="thumbMini" data-action="p">MARK</button>\n      <button class="thumbMini" data-action="r">RELAY</button>\n      <button class="thumbMini" data-action="q">FM−</button>\n      <button class="thumbMini" data-action="e">FM+</button>\n'
s=s.replace(menu_anchor,menu_extra,1)

# More truthful build copy.
s=s.replace('The chase camera now has weight rather than being bolted to the car. A distant Forth-side industrial horizon, layered haar, sodium light and speed-sensitive framing give the realm a stronger sense of scale while keeping the roads free to roam.','The broken projection chain is repaired, the square terrain slabs are gone, the mobile controls are reduced to the things you actually need while driving, and the Forth weather now renders in real screen space instead of feeding NaN geometry into the canvas.')

p.write_text(s)

bp=Path('android/app/build.gradle')
b=bp.read_text().replace('versionCode 16','versionCode 17').replace("versionName '0.16'","versionName '0.17'")
bp.write_text(b)
print('patched build 0.17 CONTROL RESET',len(s))
