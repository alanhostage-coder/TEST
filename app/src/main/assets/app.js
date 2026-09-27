(function(){
'use strict';
var SR=44100,STEPS=16,ROWS=8;
var BANKS=[
 ['A','909',['KIK','SNR','CLP','CHH','OHH','TOM','RIM','CRS']],
 ['B','707',['KIK','SNR','CLP','CHH','OHH','TOM','RIM','CRS']],
 ['C','BRK',['KIK','SNR','GHO','HAT','K+H','S+H','FIL','END']],
 ['D','L/D',['KIK','SNR','CLP','CHH','OHH','TOM','RIM','COW']],
 ['E','606',['KIK','SNR','CHH','OHH','TOM','RIM','CLP','COW']],
 ['F','SDS',['KIK','SNR','T1','T2','T3','T4','RIM','ZAP']],
 ['G','RAV',['LND','ORG','PNO','HVR','ORC','DET','BEL','ACD']]
];
var FX=['RVB','DLY','BTC','FLT','DST','CMP'];
var pat=BANKS.map(function(){return Array.from({length:8},function(){return Array(16).fill(0);});});
var usr=BANKS.map(function(){return Array(8).fill(null);}),snd=BANKS.map(function(){return Array(8).fill(null);});
var bank=0,pad=0,bpm=132,ctx=null,bus,flt,bit,dst,cmp,rvb,rvbg,dly,dlyg,fb;
var playing=false,step=0,next=0,timer=null,last=-1,gen=0,rec=null,stream=null,chunks=[];
var fx={RVB:false,DLY:false,BTC:false,FLT:false,DST:false,CMP:false};
function $(x){return document.getElementById(x);}function C(v,a,b){return Math.max(a,Math.min(b,v));}
function chance(p){return Math.random()<p;}function pick(a){return a[Math.floor(Math.random()*a.length)];}
function status(t,m){$('statusDisplay').textContent=t;if(m)$('modeDisplay').textContent=m;}
function ui(){
 BANKS.forEach(function(b,i){var x=document.createElement('button');x.className='bankbtn';x.innerHTML='<span>'+b[0]+'</span><small>'+b[1]+'</small>';x.onclick=function(){selectBank(i);};$('bankStrip').appendChild(x);});
 for(var i=0;i<8;i++){(function(i){var x=document.createElement('button');x.className='pad';x.dataset.pad=i;x.onclick=async function(){await audio();pad=i;drawPads();playPad(i,ctx.currentTime,1,bank);};$('pads').appendChild(x);})(i);}
 for(var r=0;r<8;r++){var l=document.createElement('div');l.className='rowlabel';l.dataset.rowlabel=r;$('grid').appendChild(l);for(var s=0;s<16;s++){(function(r,s){var x=document.createElement('button');x.className='step'+(s%4===0?' bar':'');x.dataset.row=r;x.dataset.step=s;x.onclick=async function(){await audio();pat[bank][r][s]=pat[bank][r][s]?0:1;if(pat[bank][r][s])playPad(r,ctx.currentTime,.9,bank);drawGrid();status(count()?'PATTERN EDIT':'EMPTY PATTERN','EDIT');};x.oncontextmenu=function(e){e.preventDefault();pat[bank][r][s]=pat[bank][r][s]===2?1:2;drawGrid();};$('grid').appendChild(x);})(r,s);}}
 FX.forEach(function(k){var x=document.createElement('button');x.className='fxbtn';x.dataset.fx=k;x.textContent=k;x.onclick=async function(){await audio();fx[k]=!fx[k];applyFx();status(k+' '+(fx[k]?'ON':'OFF'),'FX');};$('fxKeys').appendChild(x);});
 $('playBtn').onclick=start;$('stopBtn').onclick=stop;$('randomBtn').onclick=async function(){await audio();randomise();};$('clearBtn').onclick=clear;
 $('bpmDown').onclick=function(){bpm=C(bpm-2,70,190);drawBpm();};$('bpmUp').onclick=function(){bpm=C(bpm+2,70,190);drawBpm();};
 $('loadBtn').onclick=function(){$('fileInput').click();};$('fileInput').onchange=load;$('recordBtn').onclick=record;
 selectBank(0);drawBpm();applyFx();
}
async function audio(){if(!ctx){ctx=new (window.AudioContext||window.webkitAudioContext)({latencyHint:'interactive'});graph();build();}if(ctx.state==='suspended')await ctx.resume();}
function graph(){bus=ctx.createGain();flt=ctx.createBiquadFilter();flt.type='lowpass';flt.frequency.value=20000;bit=ctx.createWaveShaper();bit.curve=quant(256);dst=ctx.createWaveShaper();dst.curve=dist(0);cmp=ctx.createDynamicsCompressor();cmp.threshold.value=0;cmp.ratio.value=1;bus.connect(flt);flt.connect(bit);bit.connect(dst);dst.connect(cmp);cmp.connect(ctx.destination);rvb=ctx.createConvolver();rvb.buffer=impulse(1.7);rvbg=ctx.createGain();rvbg.gain.value=0;cmp.connect(rvb);rvb.connect(rvbg);rvbg.connect(ctx.destination);dly=ctx.createDelay(2);dlyg=ctx.createGain();dlyg.gain.value=0;fb=ctx.createGain();fb.gain.value=.32;dly.delayTime.value=60/bpm*.75;cmp.connect(dly);dly.connect(dlyg);dlyg.connect(ctx.destination);dly.connect(fb);fb.connect(dly);}
function quant(n){var a=new Float32Array(8192);for(var i=0;i<a.length;i++){var x=i/(a.length-1)*2-1;a[i]=Math.round(x*n)/n;}return a;}
function dist(k){var a=new Float32Array(8192);for(var i=0;i<a.length;i++){var x=i/(a.length-1)*2-1;a[i]=k?Math.tanh(x*k/45):x;}return a;}
function impulse(sec){var n=Math.floor(ctx.sampleRate*sec),b=ctx.createBuffer(2,n,ctx.sampleRate);for(var c=0;c<2;c++){var d=b.getChannelData(c);for(var i=0;i<n;i++)d[i]=(Math.random()*2-1)*Math.pow(1-i/n,2.6);}return b;}
function applyFx(){document.querySelectorAll('.fxbtn').forEach(function(x){x.classList.toggle('active',!!fx[x.dataset.fx]);});if(!ctx)return;rvbg.gain.value=fx.RVB?.34:0;dlyg.gain.value=fx.DLY?.28:0;bit.curve=quant(fx.BTC?18:256);flt.frequency.value=fx.FLT?2400:20000;dst.curve=dist(fx.DST?180:0);cmp.threshold.value=fx.CMP?-24:0;cmp.ratio.value=fx.CMP?7:1;}
function buf(sec,fn){var n=Math.max(32,Math.floor(sec*SR)),b=ctx.createBuffer(1,n,SR),d=b.getChannelData(0);for(var i=0;i<n;i++)d[i]=C(fn(i/SR),-1,1);return b;}
function env(t,d){return Math.exp(-t/d);}function noise(){return Math.random()*2-1;}
function kick(h){var p=0;return buf(h?.35:.52,function(t){var f=(h?115:150)*Math.exp(-t/.05)+(h?48:46);p+=6.283*f/SR;return Math.sin(p)*env(t,h?.12:.18)+(t<.006?noise()*(1-t/.006)*.1:0);});}
function snare(h){var p=0;return buf(h?.24:.34,function(t){p+=6.283*(h?170:185)/SR;return Math.sin(p)*env(t,.09)*.4+noise()*env(t,h?.065:.12)*.72;});}
function clap(){return buf(.3,function(t){var y=0;[0,.026,.052].forEach(function(o){if(t>=o)y+=noise()*env(t-o,.022);});return y*.55;});}
function hat(open,m){var p=0,q=0;return buf(open?.68:.085,function(t){p+=6.283*(6500+m*250)/SR;q+=6.283*(8900+m*190)/SR;return (noise()*.55+(Math.sign(Math.sin(p))+Math.sign(Math.sin(q)))*.22)*env(t,open?.24:.025)*.65;});}
function tom(f,d){var p=0;return buf(d*2,function(t){p+=6.283*(f+f*.7*Math.exp(-t/.06))/SR;return Math.sin(p)*env(t,d)*.8;});}
function rim(){var p=0;return buf(.08,function(t){p+=6.283*1850/SR;return (Math.sin(p)*.5+noise()*.3)*env(t,.017);});}
function crash(){return buf(1.0,function(t){return noise()*env(t,.38)*.4;});}
function cow(){var p=0,q=0;return buf(.3,function(t){p+=6.283*540/SR;q+=6.283*800/SR;return (Math.sign(Math.sin(p))*.45+Math.sign(Math.sin(q))*.4)*env(t,.12)*.55;});}
function zap(){var p=0;return buf(.3,function(t){p+=6.283*(1700*Math.exp(-t/.06)+90)/SR;return Math.sin(p)*env(t,.09)*.75;});}
function chord(notes,style){var ph=notes.map(function(){return 0;}),hz=notes.map(function(n){return 440*Math.pow(2,(n-69)/12);});return buf(style==='h'?1:.72,function(t){var y=0;for(var i=0;i<hz.length;i++){ph[i]+=6.283*hz[i]/SR;var z=ph[i];if(style==='o')y+=Math.sin(z)+.3*Math.sin(z*2);else if(style==='p')y+=Math.sin(z)+.2*Math.sin(z*2.01);else if(style==='q')y+=Math.sign(Math.sin(z));else y+=2*((z/6.283)%1)-1;}return y/hz.length*env(t,style==='h'?.34:.18)*.7;});}
function build(){snd[0]=[kick(0),snare(0),clap(),hat(0,0),hat(1,0),tom(115,.28),rim(),crash()];snd[1]=[kick(1),snare(1),clap(),hat(0,2),hat(1,2),tom(145,.19),rim(),crash()];snd[2]=[kick(1),snare(1),snare(1),hat(0,1),kick(1),snare(1),tom(125,.12),crash()];snd[3]=[kick(1),snare(0),clap(),hat(0,1),hat(1,1),tom(125,.2),rim(),cow()];snd[4]=[kick(1),snare(1),hat(0,3),hat(1,3),tom(155,.15),rim(),clap(),cow()];snd[5]=[tom(58,.34),snare(0),tom(210,.35),tom(165,.38),tom(125,.42),tom(88,.46),rim(),zap()];snd[6]=[chord([48,51,55,58],'s'),chord([48,55,60,63],'o'),chord([48,52,55],'p'),chord([41,48,53,56],'h'),chord([43,50,55,59],'q'),chord([46,49,53,56],'s'),chord([45,48,52,57],'q'),chord([36,43,46,48],'s')];}
function playPad(p,t,v,b){var x=usr[b][p]||snd[b][p];if(!x)return;var s=ctx.createBufferSource(),g=ctx.createGain();s.buffer=x;g.gain.value=v;s.connect(g);g.connect(bus);s.start(Math.max(t,ctx.currentTime));if(b===bank&&Math.abs(t-ctx.currentTime)<.05)flash(p);}
function flash(i){var x=document.querySelector('.pad[data-pad="'+i+'"]');if(x){x.classList.add('flash');setTimeout(function(){x.classList.remove('flash');},70);}}
function selectBank(i){bank=i;gen=0;document.querySelectorAll('.bankbtn').forEach(function(x,n){x.classList.toggle('active',n===i);});$('bankDisplay').textContent=BANKS[i][0]+' '+BANKS[i][1];drawPads();drawGrid();status(count()?'PATTERN READY':'EMPTY PATTERN','READY');}
function drawPads(){document.querySelectorAll('.pad').forEach(function(x,i){x.innerHTML='<span>'+(i+1)+'</span><small>'+(usr[bank][i]?'USR':BANKS[bank][2][i])+'</small>';x.classList.toggle('selected',i===pad);});document.querySelectorAll('[data-rowlabel]').forEach(function(x,i){x.textContent=(i+1)+' '+(usr[bank][i]?'USR':BANKS[bank][2][i]);});$('selectedDisplay').textContent='PAD '+(pad+1)+' / '+(usr[bank][pad]?'USR':BANKS[bank][2][pad]);}
function drawGrid(){document.querySelectorAll('.step').forEach(function(x){var v=pat[bank][+x.dataset.row][+x.dataset.step];x.classList.toggle('on',v>0);x.classList.toggle('accent',v===2);});}
function count(){var n=0;pat[bank].forEach(function(r){r.forEach(function(v){if(v)n++;});});return n;}
function drawBpm(){$('bpmDisplay').textContent=bpm;if(dly)dly.delayTime.value=60/bpm*.75;}
async function start(){await audio();if(playing)return;playing=true;step=0;next=ctx.currentTime+.05;$('playBtn').classList.add('active');status(count()?'SEQUENCING':'EMPTY / PLAY','PLAY');schedule();timer=setInterval(schedule,25);}
function stop(){playing=false;if(timer)clearInterval(timer);timer=null;$('playBtn').classList.remove('active');document.querySelectorAll('.playhead').forEach(function(x){x.classList.remove('playhead');});last=-1;status(count()?'PATTERN READY':'EMPTY PATTERN','STOP');}
function schedule(){while(playing&&next<ctx.currentTime+.12){for(var r=0;r<8;r++){var v=pat[bank][r][step];if(v)playPad(r,next,v===2?1.15:.82,bank);}mark(step,next);next+=(60/bpm)/4;step=(step+1)%16;}}
function mark(s,t){setTimeout(function(){if(!playing)return;if(last>=0)document.querySelectorAll('.step[data-step="'+last+'"]').forEach(function(x){x.classList.remove('playhead');});document.querySelectorAll('.step[data-step="'+s+'"]').forEach(function(x){x.classList.add('playhead');});last=s;},Math.max(0,(t-ctx.currentTime)*1000));}
function clear(){pat[bank].forEach(function(r){r.fill(0);});gen=0;drawGrid();status('EMPTY PATTERN','CLR');}
function randomise(){var d=(+$('density').value-1)/8;if(count()&&gen)mutate(d);else generate(d);gen++;drawGrid();status((gen===1?'GROOVE':'MUTATION '+(gen-1))+' / DENS '+$('density').value,'RND');}
function generate(d){pat[bank].forEach(function(r){r.fill(0);});if(bank===2)return breakPat(d);if(bank===6)return ravePat(d);var p=pat[bank],four=chance(.26+.38*d);if(four)[0,4,8,12].forEach(function(s){p[0][s]=chance(.22)?2:1;});else{p[0][0]=2;if(chance(.6+.2*d))p[0][8]=1;[3,6,10,11,14,15].forEach(function(s){if(chance(.08+.18*d))p[0][s]=1;});}p[1][4]=2;p[1][12]=2;if(bank!==5&&chance(.35+.3*d)){p[2][4]=1;p[2][12]=1;}var ch=bank===4?2:3,oh=bank===4?3:4;for(var s=0;s<16;s++)if(chance(s%2===0?.58+.28*d:.08+.42*d))p[ch][s]=1;[2,6,10,14].forEach(function(s){if(chance(.28+.42*d)){p[oh][s]=1;p[ch][s]=0;}});for(var r=5;r<8;r++)[7,11,14,15].forEach(function(s){if(chance(.03+.09*d))p[r][s]=1;});if(bank===5&&chance(.35+.25*d)){p[2][12]=1;p[3][13]=1;p[4][14]=1;p[5][15]=2;}}
function breakPat(d){var p=pat[bank],q=chance(.5)?[0,3,1,3,0,3,1,2,0,3,1,3,0,5,6,7]:[0,3,1,3,4,3,1,3,0,3,5,3,0,2,6,1];for(var s=0;s<16;s++){var r=q[s];if(s>10&&chance(.04+.12*d))r=pick([2,5,6,7]);p[r][s]=(s===0||s===12)?2:1;}}
function ravePat(d){var p=pat[bank],a=pick([0,1,2,5,6]),b=chance(.55)?pick([0,1,3,4,5,6,7].filter(function(x){return x!==a;})):null,q=pick([[0,3,6,10,12],[0,6,8,11,14],[2,4,7,10,14],[0,5,7,11,13]]).slice();if(d>.55&&chance(.7))q.push(pick([1,9,15]));q.forEach(function(s,i){var r=b!==null&&i>1&&chance(.28+.2*d)?b:a;p[r][s]=i===0?2:1;});if(chance(.25))p[pick([3,4])][15]=1;}
function mutate(d){var p=pat[bank],n=2+Math.floor(d*5),c=0,g=0;while(c<n&&g++<100){var r=Math.floor(Math.random()*8),s=Math.floor(Math.random()*16);if(bank!==2&&bank!==6&&((r===0&&s===0)||(r===1&&(s===4||s===12))))continue;if(bank===2){for(var rr=0;rr<8;rr++)p[rr][s]=0;p[pick(s>11?[0,2,5,6,7]:[0,1,2,3,4,5])][s]=1;}else if(bank===6){if(p[r][s]){p[r][s]=0;p[r][(s+pick([-2,-1,1,2])+16)%16]=1;}else if(chance(.35))p[r][s]=1;}else{var rr=chance(.65)?pick([3,4,5,6,7]):r;p[rr][s]=p[rr][s]?0:1;}c++;}}
async function load(e){var f=e.target.files&&e.target.files[0];if(!f)return;try{await audio();var a=await f.arrayBuffer();usr[bank][pad]=await ctx.decodeAudioData(a.slice(0));drawPads();playPad(pad,ctx.currentTime,1,bank);status('PAD '+(pad+1)+' LOADED','LOD');}catch(z){status('LOAD FAILED','ERR');}e.target.value='';}
async function record(){try{await audio();if(rec&&rec.state==='recording'){rec.stop();$('recordBtn').classList.remove('active');return;}stream=await navigator.mediaDevices.getUserMedia({audio:true});chunks=[];rec=new MediaRecorder(stream);rec.ondataavailable=function(e){if(e.data.size)chunks.push(e.data);};rec.onstop=async function(){try{var a=await new Blob(chunks).arrayBuffer();usr[bank][pad]=await ctx.decodeAudioData(a.slice(0));drawPads();playPad(pad,ctx.currentTime,1,bank);status('REC -> PAD '+(pad+1),'READY');}catch(e){status('RECORD DECODE FAILED','ERR');}stream.getTracks().forEach(function(t){t.stop();});};rec.start();$('recordBtn').classList.add('active');status('RECORDING PAD '+(pad+1),'REC');}catch(e){status('MIC PERMISSION / RECORD ERROR','ERR');}}
document.addEventListener('visibilitychange',function(){if(document.hidden)stop();});ui();
})();
