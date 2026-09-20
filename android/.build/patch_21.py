from pathlib import Path
import base64,zlib
p=Path('android/app/src/main/assets/www/index.html');s=p.read_text()
def dec(x):return zlib.decompress(base64.b64decode(x)).decode()
def rf(src,name,new):
 k='function '+name+'(';i=src.find(k);j=src.find('{',i);d=0
 if i<0:raise SystemExit(name+' missing')
 while j<len(src):
  if src[j]=='{':d+=1
  elif src[j]=='}':
   d-=1
   if d==0:return src[:i]+new+src[j+1:]
  j+=1
 raise SystemExit(name+' close missing')
INIT=dec('eNqNlE1zmzAQhu/5FdyMEpfBStyPoRxcd9pTp9P22OlBwGJrSiQiRGmm6X+v5EhIYDC9eKz3Xe3uswuULcsl5SygjMpdW1Aeoj9XQUDLcLdHAmQrWLLbpwy6IOwoK3gXncL2nEn4LZ+ejNhB9tNkMBYKUaIy5Zw1MqiApbt91JD7uoKvRMI1XmdtqbVcgDq/a8sSRLhZq8j1IBKti1SFRgeQ+yNhDKr3RJIwRknJRViBDGgaJ/StupjQmxtUfKc/0k9EHiNBVGv3IbrGLzauFdaMq37jrchBtcuaKDspuqA+VZzXqRQtuOtZ7V2nDy0pPtBKqtZRktWRfKwhXWWqcE2aZqWlUsBDCyx/jH6RqoUU38ax1r+Yc/QqYZw28JFQ5lLrk+7IOtFB/5gbMdbNqX4Y5DLMatT/7+OdpFIW0EjKiF70aSeC265nWVyIYap494zkOWdoL2Pf7gm325M8SWgNHzD28VxCNNAWKfWTuUDpQs4251ljzE28jX3f59TyJKc1ZjldQjTQlrepApa22YcYziM9HM06nTXmvNVPqvanF2eM+cX1mdFAuwykEjSSCPn89ZCcwecmd8XVgVYVkVxjGdcwSUEJO1Sw6vUx0Bt8siZxrDHEsZlstzZqvn97w4MAdqAMFlbkB41fuYF39tLdxcMA78PSF5+fYe+bog3pJOfyuPKccck7bMzJSTprOEuXz87ObxuN1MtTdrnO5oyXWPHUI+NZY9rXd9a9gIvnePE5MP4fNuzBXf39BwEcuhk=')
UPDATE=dec('eNqNUt1O2zAUvucpuotJdhI824mT0C5CFRO7QpMGLxASJ1iidmc7y9DYu2MnBtZWFG6cyOec78+nG2RjhZKLYdvWlq+HVigA/54sFqIDn9YXUHM7aLlqlDR2oU2la9dxbTWXvb0DMJFqrNYXqBm0u7I3YsOTjVJtNSp93165P9djttVVbe9QfWuAsY4G/YbJWI3cXXLtGnRbaVW334SryoaHpj/J/H2AiZI/Xb3S7decrpw4qYTh32shUe8Pw+1NrXtu15MCEACUvFTKniOM8yXChEWAnGqDTIRKDGHkdaIJybtIEMmgx7ZKHoF2YLiIZxRM6TxJMVz5sR+mQZ3mvwYum4eD0SKLgzDfc1oWiMGIorMYODh/9fiI4WcWIOkkZs6d99WOI+zs4IzF3hmLpmw3QgLikv5SoByu3OuIYy54P7Pg8rmXvt28R837CKVZiAz/r7KrUhabbURSxALs8UR4F2QULzLeG3CB4ZA6PnueuhT3lusjc4RhL4yWO7L9zn3YNph30G8TKafkD4Kn0L8LnarZXjWD8DXywP2u7EBJykl9mi0JnX3QHR+jkB/14dc38ypx7lWysD1bNYLDNUqIP2amfFbtCN5mGpGvnx8wpux1X+l+ahAu8cvKn/x7Aj3lewk=')
s=s.replace('build 0.20 WORLD COHERENCE','build 0.21 MOTION + SOUND').replace('build 0.20 · WORLD COHERENCE','build 0.21 · MOTION + SOUND')
old="let AC=null,noiseGain=null,toneGain=null,toneOsc=null,engineGain=null,engineOsc=null;"
new="let AC=null,noiseGain=null,toneGain=null,toneOsc=null,engineGain=null,engineOsc=null,engineFilter=null,engine2Gain=null,engine2Osc=null,roadGain=null,roadFilter=null,windGain=null,windFilter=null,rainGain=null,rainFilter=null;"
if old not in s:raise SystemExit('audio declaration anchor missing')
s=s.replace(old,new,1)
s=rf(s,'initAudio',INIT)
s=rf(s,'updateAudio',UPDATE)
# Adaptive detail keeps the richer scene responsive on Android rather than turning visual detail into frame drops.
old="function loop(t){if(!running)return;const dt=Math.min(.04,(t-last)/1000||.016);last=t;update(dt);draw();updateHudWithdrawal();requestAnimationFrame(loop)}"
new="let perfAvg=.016;window.__puaQuality=1;function loop(t){if(!running)return;const raw=(t-last)/1000||.016,dt=Math.min(.04,raw);last=t;perfAvg=perfAvg*.94+raw*.06;window.__puaQuality=perfAvg>.029?.68:perfAvg>.023?.82:perfAvg>.019?.92:1;update(dt);draw();updateHudWithdrawal();requestAnimationFrame(loop)}"
if old not in s:raise SystemExit('loop anchor missing')
s=s.replace(old,new,1)
# Scale expensive ambient detail with measured frame time.
old="const step=r.kind==='A'?175:235,count=Math.max(1,Math.floor(L/step));"
new="const quality=window.__puaQuality||1,step=(r.kind==='A'?175:235)/quality,count=Math.max(1,Math.floor(L/step));"
if old not in s:raise SystemExit('street quality anchor missing')
s=s.replace(old,new,1)
old="const mood=worldMood(),t=state.playSeconds*.030,cars=[]"
new="const mood=worldMood(),quality=window.__puaQuality||1,t=state.playSeconds*.030,cars=[]"
if old not in s:raise SystemExit('traffic quality declaration missing')
s=s.replace(old,new,1)
old="count=Math.max(0,Math.round(base*mood.traffic));"
new="count=Math.max(0,Math.round(base*mood.traffic*(.55+.45*quality)));"
if old not in s:raise SystemExit('traffic quality count missing')
s=s.replace(old,new,1)
old="const density=Math.floor(8+Math.min(20,speed*1.5));"
new="const density=Math.floor((8+Math.min(20,speed*1.5))*(window.__puaQuality||1));"
if old not in s:raise SystemExit('weather density anchor missing')
s=s.replace(old,new,1)
# Remove a little more synthetic high-speed streaking now that motion has actual audio/camera feedback.
s=s.replace("ctx.globalAlpha=Math.min(.12,(speed-4)*.009)","ctx.globalAlpha=Math.min(.075,(speed-4)*.006)",1)
s=s.replace('World-coherence pass: road hierarchy, wheel tracks, edge lines, cat eyes, district-specific street furniture, junction markings, dusk lighting, lane-aware traffic, camera pitch and light road-centering now work together as one driving scene.','Motion-and-sound pass: a second engine harmonic, road texture, wind and rain layers now respond to speed and surface, while frame-time-aware detail scaling protects the richer world on actual Android hardware.')
p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 20','versionCode 21').replace("versionName '0.20'","versionName '0.21'");bp.write_text(b)
print('patched build 0.21 MOTION + SOUND',len(s))
