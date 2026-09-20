const fs=require('fs'),vm=require('vm');
const html=fs.readFileSync(process.argv[2],'utf8');
const src=html.slice(html.indexOf('<script>')+8,html.indexOf('</script>'));
const noop=()=>{};
function ctx(){
  return new Proxy({
    createLinearGradient:()=>({addColorStop:noop}),
    createRadialGradient:()=>({addColorStop:noop}),
    measureText:()=>({width:10})
  },{
    get:(o,k)=>k in o?o[k]:noop,
    set:(o,k,v)=>(o[k]=v,true)
  });
}
const els=new Map();
function el(id){
  if(!els.has(id)){
    const e={
      id,style:{},
      classList:{add:noop,remove:noop,contains:()=>false,toggle:noop},
      setAttribute:noop,getAttribute:()=>null,textContent:'',value:'',files:[],
      click(){if(typeof this.onclick==='function')this.onclick({preventDefault:noop})},
      addEventListener:noop,getContext:()=>ctx(),width:0,height:0
    };
    els.set(id,e);
  }
  return els.get(id);
}
const store=new Map();
class FakeAudioContext{
  constructor(){this.sampleRate=44100;this.currentTime=0;this.destination={};this.state='running'}
  createBuffer(){return {getChannelData:()=>new Float32Array(10)}}
  createBufferSource(){return {connect(){return this},start:noop}}
  createBiquadFilter(){return {type:'',frequency:{value:0,setTargetAtTime:noop},Q:{value:0},connect(){return this}}}
  createGain(){return {gain:{value:0,setTargetAtTime:noop},connect(){return this}}}
  createOscillator(){return {type:'',frequency:{value:0,setTargetAtTime:noop},connect(){return this},start:noop}}
  resume(){return Promise.resolve()}
}
const sandbox={
  console,Math,Date,JSON,Number,String,Array,Object,Map,Set,Promise,RegExp,parseInt,parseFloat,isFinite,
  document:{getElementById:el,createElement:()=>el('created'),querySelectorAll:()=>[],body:el('body')},
  localStorage:{getItem:k=>store.has(k)?store.get(k):null,setItem:(k,v)=>store.set(k,String(v)),removeItem:k=>store.delete(k)},
  location:{hash:'',href:'http://test/'},innerWidth:1280,innerHeight:720,devicePixelRatio:1,
  addEventListener:noop,removeEventListener:noop,setInterval:()=>1,clearInterval:noop,setTimeout:noop,clearTimeout:noop,
  requestAnimationFrame:noop,cancelAnimationFrame:noop,performance:{now:()=>0},
  navigator:{mediaDevices:{getUserMedia:async()=>({getTracks:()=>[]})}},
  URL:{createObjectURL:()=>'',revokeObjectURL:noop},Blob:function(){},FileReader:function(){},
  AudioContext:FakeAudioContext,webkitAudioContext:FakeAudioContext,window:null,globalThis:null
};
sandbox.window=sandbox;sandbox.globalThis=sandbox;
try{
  vm.runInNewContext(src,sandbox,{filename:'pua.js'});
}catch(e){
  console.error('BOOT_FAIL',e.stack);
  process.exit(2);
}
if(typeof el('go').onclick!=='function'){
  console.error('BOOT_FAIL Proceed handler not bound');
  process.exit(3);
}
el('go').click();
if(el('start').style.display!=='none'){
  console.error('BOOT_FAIL Proceed did not dismiss intro');
  process.exit(4);
}
console.log('BOOT_OK Proceed handler bound and intro dismissed');
