(function(){
'use strict';

const BANKS=[
  {code:'A',name:'909',pads:['KIK','SNR','CLP','CHH','OHH','TOM','RIM','CRS']},
  {code:'B',name:'707',pads:['KIK','SNR','CLP','CHH','OHH','TOM','RIM','CRS']},
  {code:'C',name:'AMEN',pads:['KIK','SNR','GHO','HAT','K+H','S+H','FIL','END']},
  {code:'D',name:'LINN',pads:['KIK','SNR','CLP','CHH','OHH','TOM','RIM','COW']},
  {code:'E',name:'606',pads:['KIK','SNR','CHH','OHH','TOM','RIM','CLP','COW']},
  {code:'F',name:'SIMS',pads:['KIK','SNR','T1','T2','T3','T4','RIM','ZAP']},
  {code:'G',name:'RAVE',pads:['LND','ORG','PNO','HVR','ORC','DET','BEL','ACD']}
];
const FX=['RVB','DLY','BTC','FLT','DST','CMP'];
const DEMOS=[
  {name:'FOUR FLOOR',bank:0,bpm:132,make:fourFloor},
  {name:'BREAK PRESSURE',bank:2,bpm:138,make:breakPressure},
  {name:'STAB MACHINE',bank:6,bpm:145,make:stabMachine},
  {name:'ACID SIDEROOM',bank:4,bpm:136,make:acidSide},
  {name:'HALF TIME',bank:5,bpm:92,make:halfTime},
  {name:'MUTATION START',bank:1,bpm:128,make:mutationStart}
];

let ctx=null,bus=null,filter=null,crusher=null,distorter=null,compressor=null,reverb=null,reverbGain=null,delay=null,delayGain=null,feedback=null;
let audioBuffers=BANKS.map(()=>Array(8).fill(null));
let userBuffers=BANKS.map(()=>Array(8).fill(null));
let patterns=BANKS.map(()=>Array.from({length:8},()=>Array(16).fill(0)));
let bank=0,pad=0,bpm=132,density=5,playing=false,currentStep=0,nextStepTime=0,timer=null,lastStep=-1,mutationCount=0;
let fxState={RVB:false,DLY:false,BTC:false,FLT:false,DST:false,CMP:false};
let recorder=null,recordStream=null,recordChunks=[];

const $=id=>document.getElementById(id);
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const chance=p=>Math.random()<p;
const choose=a=>a[Math.floor(Math.random()*a.length)];

function init(){
  buildBanks();
  buildPads();
  buildGrid();
  buildFx();
  buildStarters();

  $('playBtn').onclick=start;
  $('stopBtn').onclick=stop;
  $('recordBtn').onclick=toggleRecord;
  $('recordPadBtn').onclick=toggleRecord;
  $('randomBtn').onclick=()=>{ randomise(); };
  $('clearBtn').onclick=clearBank;
  $('bpmDown').onclick=()=>setBpm(bpm-2);
  $('bpmUp').onclick=()=>setBpm(bpm+2);
  $('density').oninput=e=>{density=+e.target.value;$('densityValue').textContent=density;};
  $('shiftLeft').onclick=()=>shiftPattern(-1);
  $('shiftRight').onclick=()=>shiftPattern(1);

  $('loadSampleBtn').onclick=()=>$('sampleInput').click();
  $('sampleInput').onchange=loadSample;
  $('loadSongBtn').onclick=()=>$('songInput').click();
  $('songInput').onchange=loadSong;
  $('saveSongBtn').onclick=saveSong;
  $('demosBtn').onclick=()=>$('starterDialog').showModal();
  $('closeStarters').onclick=()=>$('starterDialog').close();

  selectBank(0);
  updateAll();
}

function buildBanks(){
  BANKS.forEach((b,i)=>{
    const el=document.createElement('button');
    el.className='bankbtn';
    el.innerHTML='<b>'+b.code+'</b><small>'+b.name+'</small>';
    el.onclick=()=>selectBank(i);
    $('bankStrip').appendChild(el);
  });
}

function buildPads(){
  for(let i=0;i<16;i++){
    const el=document.createElement('button');
    el.className='pad';
    el.dataset.pad=i;
    if(i<8){
      el.innerHTML='<span class="num">'+(i+1)+'</span><span class="name"></span><i class="led"></i>';
      el.onclick=async()=>{await ensureAudio();pad=i;updatePads();trigger(i,ctx.currentTime,1,bank);};
    }else{
      el.classList.add('function');
      const defs=[
        ['RND','GROOVE'],['CLR','PATTERN'],['◀','SHIFT'],['▶','SHIFT'],
        ['LOAD','SAMPLE'],['REC','PAD'],['SAVE','SONG'],['SONG','LOAD']
      ];
      const d=defs[i-8];
      el.innerHTML='<span class="num">'+(i+1)+'</span><span class="name">'+d[0]+'</span><small>'+d[1]+'</small>';
      if(i===8){el.classList.add('orange');el.onclick=randomise;}
      if(i===9)el.onclick=clearBank;
      if(i===10)el.onclick=()=>shiftPattern(-1);
      if(i===11)el.onclick=()=>shiftPattern(1);
      if(i===12)el.onclick=()=>$('sampleInput').click();
      if(i===13)el.onclick=toggleRecord;
      if(i===14)el.onclick=saveSong;
      if(i===15)el.onclick=()=>$('songInput').click();
    }
    $('pads').appendChild(el);
  }
}

function buildGrid(){
  for(let r=0;r<8;r++){
    const lab=document.createElement('div');
    lab.className='lcd-rowlabel';
    lab.dataset.rowlabel=r;
    $('lcdGrid').appendChild(lab);
    for(let s=0;s<16;s++){
      const el=document.createElement('button');
      el.className='lcd-step';
      el.dataset.row=r;
      el.dataset.step=s;
      el.onclick=async()=>{
        await ensureAudio();
        pad=r;
        const cur=patterns[bank][r][s];
        patterns[bank][r][s]=cur?0:1;
        if(!cur)trigger(r,ctx.currentTime,.9,bank);
        updateAll();
        setStatus('EDIT','STEP '+(s+1));
      };
      el.oncontextmenu=e=>{
        e.preventDefault();
        patterns[bank][r][s]=patterns[bank][r][s]===2?1:2;
        updateGrid();
      };
      $('lcdGrid').appendChild(el);
    }
  }
}

function buildFx(){
  FX.forEach(k=>{
    const el=document.createElement('button');
    el.className='fxbtn';
    el.dataset.fx=k;
    el.textContent=k;
    el.onclick=async()=>{
      await ensureAudio();
      fxState[k]=!fxState[k];
      applyFx();
      setStatus('FX',k+' '+(fxState[k]?'ON':'OFF'));
    };
    $('fxKeys').appendChild(el);
  });
}

function buildStarters(){
  DEMOS.forEach(d=>{
    const el=document.createElement('button');
    el.className='starter';
    el.innerHTML='<strong>'+d.name+'</strong><small>'+BANKS[d.bank].name+' / '+d.bpm+' BPM</small>';
    el.onclick=()=>{
      resetPatterns();
      bank=d.bank;
      bpm=d.bpm;
      d.make(patterns[bank]);
      $('starterDialog').close();
      selectBank(bank);
      updateAll();
      setStatus('SONG',d.name);
    };
    $('starterList').appendChild(el);
  });
}

function updateAll(){
  updateBanks();updatePads();updateGrid();updateFx();setBpm(bpm,false);
  $('bankDisplay').textContent=BANKS[bank].code+' '+BANKS[bank].name;
  $('padDisplay').textContent=(pad+1)+' '+(userBuffers[bank][pad]?'USR':BANKS[bank].pads[pad]);
  $('selectedDisplay').textContent='PAD '+(pad+1)+' / '+(userBuffers[bank][pad]?'USR':BANKS[bank].pads[pad]);
  $('densityValue').textContent=density;
}

function updateBanks(){
  document.querySelectorAll('.bankbtn').forEach((el,i)=>el.classList.toggle('active',i===bank));
}

function updatePads(){
  document.querySelectorAll('.pad').forEach((el,i)=>{
    if(i<8){
      el.querySelector('.name').textContent=userBuffers[bank][i]?'USR':BANKS[bank].pads[i];
      el.classList.toggle('selected',i===pad);
    }
  });
  $('padDisplay').textContent=(pad+1)+' '+(userBuffers[bank][pad]?'USR':BANKS[bank].pads[pad]);
  $('selectedDisplay').textContent='PAD '+(pad+1)+' / '+(userBuffers[bank][pad]?'USR':BANKS[bank].pads[pad]);
}

function updateGrid(){
  document.querySelectorAll('.lcd-step').forEach(el=>{
    const r=+el.dataset.row,s=+el.dataset.step,v=patterns[bank][r][s];
    el.classList.toggle('on',v>0);
    el.classList.toggle('accent',v===2);
    el.classList.toggle('row-selected',r===pad);
  });
  document.querySelectorAll('[data-rowlabel]').forEach((el,i)=>{
    el.textContent=(i+1)+' '+(userBuffers[bank][i]?'USR':BANKS[bank].pads[i]);
  });
}

function updateFx(){
  document.querySelectorAll('.fxbtn').forEach(el=>el.classList.toggle('active',!!fxState[el.dataset.fx]));
}

function selectBank(i){
  bank=clamp(i,0,BANKS.length-1);mutationCount=0;
  updateAll();
  setStatus('READY',countSteps()?'PATTERN READY':'EMPTY PATTERN');
}

function setBpm(v,announce=true){
  bpm=clamp(Math.round(v),70,190);
  $('bpmDisplay').textContent=bpm;
  if(delay)delay.delayTime.value=(60/bpm)*.75;
  if(announce)setStatus('BPM',String(bpm));
}

function setStatus(mode,text){
  $('modeDisplay').textContent=mode;
  $('statusDisplay').textContent=text;
  $('footStatus').textContent=text;
}

async function ensureAudio(){
  if(!ctx){
    ctx=new (window.AudioContext||window.webkitAudioContext)({latencyHint:'interactive'});
    makeGraph();
    makeFactorySounds();
  }
  if(ctx.state==='suspended')await ctx.resume();
}

function makeGraph(){
  bus=ctx.createGain();
  filter=ctx.createBiquadFilter();filter.type='lowpass';filter.frequency.value=20000;
  crusher=ctx.createWaveShaper();crusher.curve=quantCurve(256);
  distorter=ctx.createWaveShaper();distorter.curve=distCurve(0);
  compressor=ctx.createDynamicsCompressor();compressor.threshold.value=0;compressor.ratio.value=1;
  bus.connect(filter);filter.connect(crusher);crusher.connect(distorter);distorter.connect(compressor);compressor.connect(ctx.destination);

  reverb=ctx.createConvolver();reverb.buffer=makeImpulse(1.6);
  reverbGain=ctx.createGain();reverbGain.gain.value=0;
  compressor.connect(reverb);reverb.connect(reverbGain);reverbGain.connect(ctx.destination);

  delay=ctx.createDelay(2);delay.delayTime.value=(60/bpm)*.75;
  delayGain=ctx.createGain();delayGain.gain.value=0;
  feedback=ctx.createGain();feedback.gain.value=.28;
  compressor.connect(delay);delay.connect(delayGain);delayGain.connect(ctx.destination);delay.connect(feedback);feedback.connect(delay);
}

function applyFx(){
  updateFx();
  if(!ctx)return;
  reverbGain.gain.value=fxState.RVB?.32:0;
  delayGain.gain.value=fxState.DLY?.25:0;
  crusher.curve=quantCurve(fxState.BTC?16:256);
  filter.frequency.value=fxState.FLT?2300:20000;
  distorter.curve=distCurve(fxState.DST?170:0);
  compressor.threshold.value=fxState.CMP?-25:0;
  compressor.ratio.value=fxState.CMP?8:1;
}

function makeBuffer(seconds,fn){
  const n=Math.max(64,Math.floor(seconds*ctx.sampleRate)),b=ctx.createBuffer(1,n,ctx.sampleRate),d=b.getChannelData(0);
  for(let i=0;i<n;i++)d[i]=clamp(fn(i/ctx.sampleRate),-1,1);
  return b;
}
const env=(t,d)=>Math.exp(-t/d),noise=()=>Math.random()*2-1;

function kick(soft=false){let p=0;return makeBuffer(soft?.38:.52,t=>{const f=(soft?105:145)*Math.exp(-t/.05)+(soft?48:45);p+=Math.PI*2*f/ctx.sampleRate;return Math.sin(p)*env(t,soft?.14:.18)+(t<.005?noise()*(1-t/.005)*.08:0);});}
function snare(short=false){let p=0;return makeBuffer(short?.24:.34,t=>{p+=Math.PI*2*(short?165:185)/ctx.sampleRate;return Math.sin(p)*env(t,.08)*.35+noise()*env(t,short?.06:.11)*.7;});}
function clap(){return makeBuffer(.3,t=>{let y=0;[0,.026,.052].forEach(o=>{if(t>=o)y+=noise()*env(t-o,.022);});return y*.52;});}
function hat(open=false,shift=0){let p=0,q=0;return makeBuffer(open?.72:.09,t=>{p+=Math.PI*2*(6500+shift*240)/ctx.sampleRate;q+=Math.PI*2*(9000+shift*170)/ctx.sampleRate;return (noise()*.52+(Math.sign(Math.sin(p))+Math.sign(Math.sin(q)))*.2)*env(t,open?.26:.025)*.62;});}
function tom(f,d){let p=0;return makeBuffer(d*2,t=>{p+=Math.PI*2*(f+f*.65*Math.exp(-t/.06))/ctx.sampleRate;return Math.sin(p)*env(t,d)*.8;});}
function rim(){let p=0;return makeBuffer(.08,t=>{p+=Math.PI*2*1850/ctx.sampleRate;return (Math.sin(p)*.5+noise()*.3)*env(t,.018);});}
function crash(){return makeBuffer(1.05,t=>noise()*env(t,.4)*.4);}
function cow(){let p=0,q=0;return makeBuffer(.3,t=>{p+=Math.PI*2*540/ctx.sampleRate;q+=Math.PI*2*800/ctx.sampleRate;return (Math.sign(Math.sin(p))*.42+Math.sign(Math.sin(q))*.38)*env(t,.12)*.55;});}
function zap(){let p=0;return makeBuffer(.32,t=>{p+=Math.PI*2*(1700*Math.exp(-t/.06)+90)/ctx.sampleRate;return Math.sin(p)*env(t,.09)*.74;});}
function chord(notes,style='s'){const ph=notes.map(()=>0),hz=notes.map(n=>440*Math.pow(2,(n-69)/12));return makeBuffer(style==='h'?1.0:.75,t=>{let y=0;for(let i=0;i<hz.length;i++){ph[i]+=Math.PI*2*hz[i]/ctx.sampleRate;const z=ph[i];if(style==='o')y+=Math.sin(z)+.28*Math.sin(z*2);else if(style==='p')y+=Math.sin(z)+.18*Math.sin(z*2.01);else if(style==='q')y+=Math.sign(Math.sin(z));else y+=2*((z/(Math.PI*2))%1)-1;}return y/hz.length*env(t,style==='h'?.34:.18)*.7;});}

function makeFactorySounds(){
  audioBuffers[0]=[kick(false),snare(false),clap(),hat(false,0),hat(true,0),tom(115,.28),rim(),crash()];
  audioBuffers[1]=[kick(true),snare(true),clap(),hat(false,2),hat(true,2),tom(145,.19),rim(),crash()];
  audioBuffers[2]=[kick(true),snare(true),snare(true),hat(false,1),kick(true),snare(true),tom(125,.12),crash()];
  audioBuffers[3]=[kick(true),snare(false),clap(),hat(false,1),hat(true,1),tom(125,.2),rim(),cow()];
  audioBuffers[4]=[kick(true),snare(true),hat(false,3),hat(true,3),tom(155,.15),rim(),clap(),cow()];
  audioBuffers[5]=[tom(58,.34),snare(false),tom(210,.35),tom(165,.38),tom(125,.42),tom(88,.46),rim(),zap()];
  audioBuffers[6]=[
    chord([48,51,55,58],'s'),chord([48,55,60,63],'o'),chord([48,52,55],'p'),chord([41,48,53,56],'h'),
    chord([43,50,55,59],'q'),chord([46,49,53,56],'s'),chord([45,48,52,57],'q'),chord([36,43,46,48],'s')
  ];
}

function trigger(p,time,vel=1,b=bank){
  const buf=userBuffers[b][p]||audioBuffers[b][p];if(!buf||!ctx)return;
  const src=ctx.createBufferSource(),g=ctx.createGain();
  src.buffer=buf;g.gain.value=vel;src.connect(g);g.connect(bus);src.start(Math.max(time,ctx.currentTime));
  if(b===bank&&Math.abs(time-ctx.currentTime)<.05)flashPad(p);
}

function flashPad(i){
  const el=document.querySelector('.pad[data-pad="'+i+'"]');if(!el)return;
  el.classList.add('flash');setTimeout(()=>el.classList.remove('flash'),75);
}

async function start(){
  await ensureAudio();if(playing)return;
  playing=true;currentStep=0;nextStepTime=ctx.currentTime+.05;
  $('playBtn').classList.add('active');setStatus('PLAY','SEQUENCING');
  schedule();timer=setInterval(schedule,25);
}
function stop(){
  playing=false;if(timer)clearInterval(timer);timer=null;
  $('playBtn').classList.remove('active');
  document.querySelectorAll('.lcd-step.current').forEach(el=>el.classList.remove('current'));
  lastStep=-1;setStatus('STOP',countSteps()?'PATTERN READY':'EMPTY PATTERN');
}
function schedule(){
  while(playing&&nextStepTime<ctx.currentTime+.12){
    for(let r=0;r<8;r++){const v=patterns[bank][r][currentStep];if(v)trigger(r,nextStepTime,v===2?1.15:.82,bank);}
    markStep(currentStep,nextStepTime);
    nextStepTime+=(60/bpm)/4;currentStep=(currentStep+1)%16;
  }
}
function markStep(s,t){
  setTimeout(()=>{
    if(!playing)return;
    if(lastStep>=0)document.querySelectorAll('.lcd-step[data-step="'+lastStep+'"]').forEach(el=>el.classList.remove('current'));
    document.querySelectorAll('.lcd-step[data-step="'+s+'"]').forEach(el=>el.classList.add('current'));
    lastStep=s;
  },Math.max(0,(t-ctx.currentTime)*1000));
}

function countSteps(){let n=0;patterns[bank].forEach(r=>r.forEach(v=>{if(v)n++;}));return n;}
function resetPatterns(){patterns=BANKS.map(()=>Array.from({length:8},()=>Array(16).fill(0)));}
function clearBank(){patterns[bank].forEach(r=>r.fill(0));mutationCount=0;updateGrid();setStatus('CLR','CURRENT BANK CLEARED');}
function shiftPattern(dir){patterns[bank].forEach(r=>{if(dir<0)r.push(r.shift());else r.unshift(r.pop());});updateGrid();setStatus('SHIFT',dir<0?'LEFT':'RIGHT');}

function randomise(){
  if(countSteps()&&mutationCount>0)mutate();
  else generate();
  mutationCount++;updateGrid();setStatus('RND',mutationCount===1?'GROOVE '+density:'MUTATION '+(mutationCount-1));
}
function generate(){
  patterns[bank].forEach(r=>r.fill(0));
  const d=(density-1)/8;
  if(bank===2){breakPattern(d);return;}
  if(bank===6){ravePattern(d);return;}
  const p=patterns[bank];
  if(chance(.28+.35*d)){[0,4,8,12].forEach(s=>p[0][s]=chance(.2)?2:1);}else{
    p[0][0]=2;if(chance(.7))p[0][8]=1;[3,6,10,11,14,15].forEach(s=>{if(chance(.06+.15*d))p[0][s]=1;});
  }
  p[1][4]=2;p[1][12]=2;
  const ch=bank===4?2:3,oh=bank===4?3:4;
  for(let s=0;s<16;s++)if(chance(s%2===0?.58+.27*d:.06+.36*d))p[ch][s]=1;
  [2,6,10,14].forEach(s=>{if(chance(.26+.35*d)){p[oh][s]=1;p[ch][s]=0;}});
  if(bank!==5&&chance(.4+.25*d)){p[2][4]=1;p[2][12]=1;}
  for(let r=5;r<8;r++)for(const s of [7,11,14,15])if(chance(.02+.08*d))p[r][s]=1;
  if(bank===5&&chance(.45)){p[2][12]=1;p[3][13]=1;p[4][14]=1;p[5][15]=2;}
}
function breakPattern(d){
  const p=patterns[bank],seq=choose([
    [0,3,1,3,0,3,1,2,0,3,1,3,0,5,6,7],
    [0,3,1,3,4,3,1,3,0,3,5,3,0,2,6,1]
  ]);
  seq.forEach((r,s)=>{let rr=r;if(s>11&&chance(.05+.1*d))rr=choose([2,5,6,7]);p[rr][s]=(s===0||s===12)?2:1;});
}
function ravePattern(d){
  const p=patterns[bank],a=choose([0,1,2,5,6]),b=chance(.55)?choose([0,1,3,4,5,6,7].filter(x=>x!==a)):null;
  const hits=choose([[0,3,6,10,12],[0,6,8,11,14],[2,4,7,10,14],[0,5,7,11,13]]).slice();
  if(d>.55&&chance(.7))hits.push(choose([1,9,15]));
  hits.forEach((s,i)=>{const r=b!==null&&i>1&&chance(.3+.18*d)?b:a;p[r][s]=i===0?2:1;});
}
function mutate(){
  const p=patterns[bank],d=(density-1)/8,n=2+Math.floor(d*5);let c=0,guard=0;
  while(c<n&&guard++<120){
    const r=Math.floor(Math.random()*8),s=Math.floor(Math.random()*16);
    if(bank!==2&&bank!==6&&((r===0&&s===0)||(r===1&&(s===4||s===12))))continue;
    if(bank===2){
      for(let rr=0;rr<8;rr++)p[rr][s]=0;p[choose(s>11?[0,2,5,6,7]:[0,1,2,3,4,5])][s]=1;
    }else if(bank===6){
      if(p[r][s]){p[r][s]=0;p[r][(s+choose([-2,-1,1,2])+16)%16]=1;}else if(chance(.32))p[r][s]=1;
    }else{
      const rr=chance(.68)?choose([3,4,5,6,7]):r;p[rr][s]=p[rr][s]?0:1;
    }
    c++;
  }
}

async function loadSample(e){
  const file=e.target.files&&e.target.files[0];if(!file)return;
  try{
    await ensureAudio();
    const arr=await file.arrayBuffer();
    userBuffers[bank][pad]=await ctx.decodeAudioData(arr.slice(0));
    updatePads();trigger(pad,ctx.currentTime,1,bank);setStatus('LOAD','SAMPLE -> PAD '+(pad+1));
  }catch(err){setStatus('ERR','SAMPLE LOAD FAILED');}
  e.target.value='';
}

async function toggleRecord(){
  try{
    await ensureAudio();
    if(recorder&&recorder.state==='recording'){
      recorder.stop();$('recordBtn').classList.remove('active');return;
    }
    recordStream=await navigator.mediaDevices.getUserMedia({audio:true});
    recordChunks=[];recorder=new MediaRecorder(recordStream);
    recorder.ondataavailable=e=>{if(e.data.size)recordChunks.push(e.data);};
    recorder.onstop=async()=>{
      try{
        const arr=await new Blob(recordChunks).arrayBuffer();
        userBuffers[bank][pad]=await ctx.decodeAudioData(arr.slice(0));updatePads();trigger(pad,ctx.currentTime,1,bank);
        setStatus('REC','RECORDED -> PAD '+(pad+1));
      }catch(e){setStatus('ERR','RECORD DECODE FAILED');}
      recordStream.getTracks().forEach(t=>t.stop());
    };
    recorder.start();$('recordBtn').classList.add('active');setStatus('REC','RECORDING PAD '+(pad+1));
  }catch(err){setStatus('ERR','MIC PERMISSION / RECORD');}
}

function songObject(){
  return {
    app:'ALAN',format:2,bpm,density,bank,pad,
    fx:fxState,
    patterns:patterns,
    created:new Date().toISOString()
  };
}
function saveSong(){
  const json=JSON.stringify(songObject());
  const name='ALAN-'+new Date().toISOString().slice(0,19).replace(/[:T]/g,'-')+'.alan';
  if(window.AlanNative&&AlanNative.saveSong){
    AlanNative.saveSong(json,name);setStatus('SAVE','CHOOSE FILE LOCATION');
  }else{
    const blob=new Blob([json],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');
    a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
}
async function loadSong(e){
  const file=e.target.files&&e.target.files[0];if(!file)return;
  try{
    const obj=JSON.parse(await file.text());
    if(obj.app!=='ALAN'||!Array.isArray(obj.patterns))throw new Error('bad');
    if(obj.patterns.length!==BANKS.length)throw new Error('banks');
    patterns=obj.patterns.map(b=>b.map(r=>r.slice(0,16).map(v=>v===2?2:(v?1:0))));
    bpm=clamp(+obj.bpm||132,70,190);density=clamp(+obj.density||5,1,9);bank=clamp(+obj.bank||0,0,BANKS.length-1);pad=clamp(+obj.pad||0,0,7);
    fxState=Object.assign({RVB:false,DLY:false,BTC:false,FLT:false,DST:false,CMP:false},obj.fx||{});
    $('density').value=density;updateAll();applyFx();setStatus('SONG','LOADED '+file.name);
  }catch(err){setStatus('ERR','NOT A VALID ALAN SONG');}
  e.target.value='';
}

function quantCurve(n){const a=new Float32Array(8192);for(let i=0;i<a.length;i++){const x=i/(a.length-1)*2-1;a[i]=Math.round(x*n)/n;}return a;}
function distCurve(k){const a=new Float32Array(8192);for(let i=0;i<a.length;i++){const x=i/(a.length-1)*2-1;a[i]=k?Math.tanh(x*k/45):x;}return a;}
function makeImpulse(sec){const n=Math.floor(ctx.sampleRate*sec),b=ctx.createBuffer(2,n,ctx.sampleRate);for(let c=0;c<2;c++){const d=b.getChannelData(c);for(let i=0;i<n;i++)d[i]=(Math.random()*2-1)*Math.pow(1-i/n,2.6);}return b;}

function fourFloor(p){[0,4,8,12].forEach(s=>p[0][s]=2);[4,12].forEach(s=>p[1][s]=2);for(let s=0;s<16;s+=2)p[3][s]=1;[2,6,10,14].forEach(s=>p[4][s]=1);}
function breakPressure(p){[0,4,8,12].forEach(s=>p[0][s]=1);[4,12].forEach(s=>p[1][s]=2);[2,6,10,14].forEach(s=>p[3][s]=1);p[6][14]=1;p[7][15]=2;}
function stabMachine(p){[0,6,8,11,14].forEach((s,i)=>p[i%2?3:0][s]=i===0?2:1);p[5][3]=1;p[6][13]=1;}
function acidSide(p){[0,4,8,12].forEach(s=>p[0][s]=2);[4,12].forEach(s=>p[1][s]=2);for(let s=0;s<16;s+=2)p[2][s]=1;[2,6,10,14].forEach(s=>p[3][s]=1);p[7][7]=1;}
function halfTime(p){[0,8].forEach(s=>p[0][s]=2);p[1][8]=2;p[2][12]=1;p[3][13]=1;p[4][14]=1;p[5][15]=2;}
function mutationStart(p){p[0][0]=2;p[0][8]=1;p[1][4]=2;p[1][12]=2;for(let s=0;s<16;s+=2)p[3][s]=1;p[4][6]=1;p[4][14]=1;p[6][15]=1;}

document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
window.addEventListener('error',e=>{try{setStatus('ERR','UI '+e.message);}catch(_){}});
init();
})();