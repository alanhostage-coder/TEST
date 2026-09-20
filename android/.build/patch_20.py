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
ROAD=dec('eNqFVk1v2zgQve+vYFGsLdkULcqW7darLnLPAkVbYA+LPVAiHROhJINiailx/nuHlOXIX+nBEod8ImfevBl6/VRkRpYF4prtvpWM06WnccZyvPNf/kAoK4vKIF4nmtRRAA+KeQNGY42G4vvkH2Y2ZNNsS+PxGhb9/Z7iok4C3kzucdEkvIZ3ZcS2arE5qz0aYjfOhFTe/WQ+8328YWoNO+9GJF7ByetSe0oYJBP3bUBX8ksSrmQQOMc610yYyIlDYEMTT46pfzCz0HlNx7wemRBM5zeYjTNpb5WC2Vulq94BLNmVWvEf5fdMC1F4sO24qEfWW7vnuGgOY5b7OL0EBz1wcALOzsG0B6ZnYH4JHvfAJ2607su194GRn7KSqRL7/Ye0N856Y96NfQjYyOJJ9MPnYms2iceIG4zTwzs7vHn79kckivGacfGWYxItMQ3c8gS8ImumR2Sx9PFOmDfUQQi5LDwyW2JvNxjsiGay2O9D2HW6HLdTmSqfeDsXxv4hxMzU5EGVKVN3arthiXWgXdnCpl9L1Xj/MZziDPP/sSaPsuBJkgzvhn8PP0bpNIzE8PPw4zSaLqbx8LDnZII4049Co91GCIWMZtljhR6F2CKzEah60muWCbTWZY60YFwWD4hViKEKRgoWFDOoMlpuezQqFt7WEYQZ9rXU2jbritHbeW9h9PKzfv5UGt7WZHdwcHlwSm+rszs4uHEwZAXiLx/Fd9MokQz1Q8psydMpphEmNPKHKwtSshD/Sg76ehPNAoPWqowpARpzb39EydJ3H6TiQRZfAeu1dl7+FD9KD8glNbbPxj9u7Oapm6fdfIdPHT69wKcOnx7xbRTeW0GBdL+QMPJfWnLzOrSlUUNZ1CDMGOeNm2hgomknamhKGSD4EeEmGphwiNU1DY/gnNV1GqNwgaMwwnQ5w1Bh7zA5i69SCdXzHpcQko3ihBcIwvp9yslrVy2CPwhkkRWaQJnoFFViyzSz18rNKoVOEF1EeFqhh3BjCHeG6acQkxkI5/NBTQvQ0mKB6Xz+GxriHg28o4HE7ysKcorZmTogg5ifKQnyjtMzHGQbZ9cVBGyl1i5QJgqjW9pQWagGHugOabiAq05rfTYGA/lnBMPwqLwrVW0rua3enF5pNnAPu4sRgo9ct4ELujdhyxdOzcPuOhgMcnq8Gl6uJzGe3ZJp9AlH0QxyRzFZzN7JzxzbM9v8wIFdgubh+zK1FZyfF3Bu6ze/KN/Xo1YzZoZVIBqBtqUsTIUKwbRr6xC/0OwW91PL/WDgLrO/PoVvaTjj2RENndKVumdJhjbpjCO/v6N03raEtVTqhNAp1H0Edb+ADjp3HdR58HzSO/OWPyjzQ5Xbbb6JzMC5dfAM603wDO06xs+jCH5k0ZJjf+fuwL+g118TNzjD')
STREET=dec('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')
TRAFFIC=dec('eNqNVdtu2zgQfe9XGAg2FiWaESkx9tphgjwu0ALFJm9FC9ASbSlVJIVUYgmp/32HpJ3UuXVhQKLOzJk5HM7Qq/s668qmHuVabq61XK3KLMiK+/qnwZm8RY+fRqOsqU03um2aXGwaXeVfYBUg3AnTyU6RtpLDlQKn3IQkTmLgaSO+fce5HEQQvHI6SU5j9BeNKDywua/FF9kVxJR1AITQfXz9J2ST3eqEoZDwiHBcleuiMwIoZyRhC1C2anTg1WWjZjXyupFFK9WNdCnihS7PMqIbmRtSqXrdFYBEEXr0NC12xm+6/I6X0iihyc+yzoUQ48vxBZtTnDX3dedF3so+iLFbakDzwDJCWxnS+dohtNinv4HsN2eOvbh5TpmXWhTSFEFGsj7SJb6JYDVgo1T+I+5TTtE54Rd0PoHqtAAKKCqPPqRwKFHMcVuIwPndYOd56HSKoi50EUPQYIvftqItzuKLtojovC1w3sPuezaBB8X5AB+D/Rgo/uz3Xwxt0wV5D0b06xfFdS8m+XDyGdeDyHt4V7JWIjgooSabkNDZ3L9TZJNjl4hGeR+2bVT3oeVhlxDAwYGDB1vfc9fNVaaVqoMeD64xF+UqaMlDacplpY6PW5KrtivOGI9jZBuQtPdQiEfr3mI5N459Wa8r5UL0NjeJU6dmsDn3HzY4NoXM1XxXS2gYW87nSk7dCY2PTvPpdJqM5+MjHvMlz8YYAmzRdmuHxmowje6CQOIlEudLstM4kfsVetHDUrsuBqabu/3k3T03H6Gnvv1uYVwYYXbWIJrJZKUQwpuNoNPwDheFgNci63pi5IMKkFtCi9amgmkMPKvfsQdv1k23t0mPrKtmKavLqi3kbxJYiunEM90uTqBiZCV1SKbM7Qh0A3lVVtVVN1RKjPV6KWFu7A/YaOyCL9W6rL9C1J06VVVlaxT4wb5gD5uNDQhbgemfOe7T1eAJNkHwZkIrzp3gm4lumwd13QQTm4AzHHu0KusnNGV4UhQHuIWT9E34OUZWNUb9lul9heMjxpM4YeM/KqQzmzQkf7NXiRl715RQb0pnr3dH40Pb/1dt6wodfh5f+CNlCccMVNApx2TGEEyCx2OGOcdp4tGnqP+qrPPyEi+Bp7vDpiQN79D7jjQ+dHTi4AbwfwnHx0/K/HJ/G0x5DNfui06Gm3Lx8jTUKuez/MPTcI2xOwz+quDpLEqtPmum5PRdu2V/WPftU921Ml2jYXgB2X7a/geqg2qB')
CAR=dec('eNqNVF1v2jAUfd+vSNUHEuS4sfNl1qJpmjRpD5OqbdIepj04wdCoJgm2YUWl/312nEJJQjYhRLi5PufY5/gut2Wuiqp0FoL+ued0z8QnKnDg1iCnayC3pff8znGKpXtVHw5XNdwVssg48wRTW1He5lUplbOZf6XqAa7pkwvTBNg/ReliGMWghjKneoV3m6snKOmOufZRCVpKThVza/ik2/beraWSShdhVX6uKuU9m9Zlwfl3tedsPhGrjLoBMB+IE2/SQGVsVZT3mraFZpwXtWS6D083INZf82vWNNruv0yxbTTA7RqpRPXIWpbrPM0DurDovCjZz2KhHk7bRADBcLrxBtnX1Y79qDS5j4LXHoNha7hT8jUOOGKd1nb7ztqsWPe0iaPuZU6yaPhUqMgbUS3S6GkIJlUlDIN1+kVbY83mjJbz1iOpGBOHQ+BN33geW1iaybZr500hjrzpxvh77rwBA4H3+uKCzyH+p8+R8diYnMJ41GrNdHPjqL3eYJ/0GqVohsjkuOAby5Xro5mG9FEbpeTVhGMDinrvLU1WLfYDLJTSiCwnY+HxsY4OQN2soKRh6teDpp506pfKwyjnlDmvJHsj7Oz8BKPCWXEqhw4Rz8I4JOPbsycadRQMV5Hx1Se9PZ+XR/Vm23XNhEPLhVOb4A2oTtJEy+5ZT5o0hebE8OnKd4OKsR41KAAo1XFNiNeFOQaE2FlkE9/cp0zQx6JczR/ZXv6aOJPfh0N7be58GMYdurb7Q0sbBSCegQgDOIu9yXtbRYSAiICQAEiCnhRkMtoIauYiHIhzMNDRjuZteQcxsVN5xauM8o+8fqBzGCS9WcRInqaL8RxYrp63cSMSDddPU/WC5yOEw3wX6P6L7aXN0nFivnv5C0y2R5A=')
MINI=dec('eNp9UtFu2yAUfe9XWIoUQ0eYTZytbcqqas+VqrXSngmGgOKYCpPaVpV/Hw5kXrJssmzwufdyzzlcuau506ZOSsvaJ13rJ/YG4MdVknBTNy5p6Za9fcetLp1CKvwoodfKLbfcdbgR7tWyupHGbkGOMv8cvjCEeSWY/SG4A0OkRSriUlfVi+srQdNJVuZ5nqVj4DQ/8Gg488k4WywQ72j7mSDeUzUsinK1qzfNozW7ugSNY07gDoW1RwQuvRhPD4SDeGJkwhUcEXtAsDWsbOBHUOWs2YhA0OKNrktKafqYPqR2vWKAzAki8wyR/AbheQHTuwt4fgOjpkrX4udg4OlZBBd3OSYhZyXWun5mToHo0Na8i1cDePcJWNzls6gLXh+c8OoHvD/ifcTh2HEsJv8oJpeLg3gA9ye+HVwK+VZUrPdWhUBHY5vzLj2Nfc7aLLUE3TeaTafdPW2n0/6w7++piu6Pw2Gx4Mo8pJNbubpl3Ps8kRnjXxfn09LNCOr9W6AC7gfiQQl7F0c/3TCllefhXfEGRNSagVocGnZhOKWU6f9v6MvvYY+uzwo0m+PFX+CI8co04s+jho7HvRWNM9bzvtr/AheaMBU=')
s=s.replace('build 0.19 STREET LEVEL','build 0.20 WORLD COHERENCE').replace('build 0.19 · STREET LEVEL','build 0.20 · WORLD COHERENCE')
s=rf(s,'drawRoad18',ROAD)
s=rf(s,'drawTraffic',TRAFFIC)
s=rf(s,'drawMiniMap',MINI)
# Insert world-coherence helpers before building rendering.
a='function drawBuilding(b,cam){';i=s.find(a)
if i<0:raise SystemExit('drawBuilding anchor missing')
s=s[:i]+STREET+'\n'+CAR+'\n'+s[i:]
# District-aware building palette.
old="const wall=b.industrial?(b.t>.55?'#62635d':'#535953'):(b.t>.6?'#686158':'#575b56'),dark=b.industrial?'#3f4541':'#454943',roof=b.industrial?'#74736a':'#696a62';"
new="const zone=district20(b.x,b.y),wall=b.industrial?(zone.id==='industrial'?'#595e5a':zone.wall):(zone.id==='estate'?'#62665d':zone.wall),dark=zone.id==='coast'?'#48514c':b.industrial?'#3d4440':'#454943',roof=zone.id==='industrial'?'#6e7068':'#6b6d64';"
if old not in s:raise SystemExit('building palette anchor missing')
s=s.replace(old,new,1)
# Road-authoritative physics plus mild lane centring when the driver is not fighting the wheel.
old="function update(dt){state.playSeconds+=dt;const onRoad=roadDistance(state.x,state.y)<62;const ground=terrain(state.x,state.y);const priorV=Math.abs(state.v);"
new="function update(dt){state.playSeconds+=dt;const nr20=nearestRoadPoint18(state.x,state.y),onRoad=!!(nr20&&nr20.d<62);const ground=terrain(state.x,state.y);const priorV=Math.abs(state.v);"
if old not in s:raise SystemExit('update road anchor missing')
s=s.replace(old,new,1)
old="state.x+=Math.cos(state.a)*state.v*dt*60;state.y+=Math.sin(state.a)*state.v*dt*60}"
new="state.x+=Math.cos(state.a)*state.v*dt*60;state.y+=Math.sin(state.a)*state.v*dt*60;if(nr20&&nr20.d<82&&Math.abs(state.v)>1&&Math.abs(steer)<.56){const pull=.0065*(1-Math.abs(steer));state.x+=(nr20.x-state.x)*pull*dt*60;state.y+=(nr20.y-state.y)*pull*dt*60}}"
if old not in s:raise SystemExit('vehicle movement anchor missing')
s=s.replace(old,new,1)
# Camera gets a little pitch under acceleration/braking rather than staying mechanically fixed.
old="const bump=Math.sin(state.playSeconds*(4.4+speed*.15))*Math.min(2.2,speed*.12),cam={x:rig.x,y:rig.y,fx:rig.fx,fy:rig.fy,height:state.onFoot?79:99+speed*1.8+bump,horizon:H*(state.onFoot?.335:.292-Math.min(.010,speed*.0011)),focal:Math.min(W,H)*(.60+Math.min(.045,speed*.004)),near:18,far:3600};"
new="window.__puaCamV=window.__puaCamV==null?speed:window.__puaCamV+(speed-window.__puaCamV)*.10;const accel=speed-window.__puaCamV,bump=Math.sin(state.playSeconds*(4.4+speed*.15))*Math.min(1.8,speed*.10),pitch=Math.max(-5,Math.min(5,accel*2.8)),cam={x:rig.x,y:rig.y,fx:rig.fx,fy:rig.fy,height:state.onFoot?79:99+speed*1.75+bump-pitch*.18,horizon:H*(state.onFoot?.335:.292-Math.min(.010,speed*.0011))+pitch,focal:Math.min(W,H)*(.60+Math.min(.050,speed*.0045)),near:18,far:3600};"
if old not in s:raise SystemExit('camera anchor missing')
s=s.replace(old,new,1)
# Replace the street/world calls with the richer, district-aware pass and junction detail.
old="drawStreetLife19(chunks,cam,w);drawTraffic(chunks,cam);drawForthWeather(cam,speed,w);"
new="drawStreetLife20(chunks,cam,w,sun);drawJunctions20(chunks,cam);drawTraffic(chunks,cam);drawForthWeather(cam,speed,w);"
if old not in s:raise SystemExit('street render call missing')
s=s.replace(old,new,1)
old="const p=worldToScreen(state.x,state.y,cam);drawPlayerCar19(p,cam)"
new="const p=worldToScreen(state.x,state.y,cam);drawPlayerCar20(p,cam,sun)"
if old not in s:raise SystemExit('player car call missing')
s=s.replace(old,new,1)
# Reduce full-screen vignette slightly now that the scene has more real depth.
s=s.replace("v.addColorStop(1,'rgba(10,12,11,.24)')","v.addColorStop(1,'rgba(10,12,11,.17)')",1)
s=s.replace('Street-level pass: pavements, lamps, signs, trees, fencing, building shadows, lane-separated traffic and a more convincing player car now sit on the persistent road world. Road physics now follow the actual road rather than hidden terrain noise.','World-coherence pass: road hierarchy, wheel tracks, edge lines, cat eyes, district-specific street furniture, junction markings, dusk lighting, lane-aware traffic, camera pitch and light road-centering now work together as one driving scene.')
p.write_text(s)
bp=Path('android/app/build.gradle');b=bp.read_text().replace('versionCode 19','versionCode 20').replace("versionName '0.19'","versionName '0.20'");bp.write_text(b)
print('patched build 0.20 WORLD COHERENCE',len(s))
