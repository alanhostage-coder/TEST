'use strict';
// Formatting stays in the existing string CRM property. Never execute user HTML.
const TEMPLATES={
  bold:'**Important point**',
  italic:'*Emphasised point*',
  heading:'## Section heading',
  bullets:'- First item\n- Second item',
  numbers:'1. First item\n2. Second item',
  link:'[Link label](https://your-link)'
};
function appendFormat(value,kind){
  const before=String(value||'');
  if(!Object.prototype.hasOwnProperty.call(TEMPLATES,kind))return before;
  return before+(before.trim()?'\n\n':'')+TEMPLATES[kind];
}
function inlineParts(line){
 const input=String(line||'');
 const tokens=/(\*\*[^*\n]+\*\*|\*[^*\n]+\*|\[[^\]\n]+\]\(https:\/\/[^\s)]+\))/g;
 const result=[];let cursor=0,match;
 while((match=tokens.exec(input))){
   if(match.index>cursor)result.push({kind:'plain',text:input.slice(cursor,match.index)});
   const token=match[0];
   if(token.startsWith('**'))result.push({kind:'bold',text:token.slice(2,-2)});
   else if(token.startsWith('*'))result.push({kind:'italic',text:token.slice(1,-1)});
   else {
     const parsed=/^\[([^\]]+)\]\((https:\/\/[^)\s]+)\)$/.exec(token);
     const valid=parsed&&/^https:\/\/[a-z0-9.-]+\.[a-z]{2,}(?:[/?#][^\s]*)?$/i.test(parsed[2]);
     if(valid)result.push({kind:'link',text:parsed[1],url:parsed[2]});
     else result.push({kind:'plain',text:token});
   }
   cursor=tokens.lastIndex;
 }
 if(cursor<input.length)result.push({kind:'plain',text:input.slice(cursor)});
 return result;
}
function previewLines(markdown){
 return String(markdown||'').split(/\r?\n/).slice(0,120).map(line=>{
   const h=/^#{1,3}\s+(.+)$/.exec(line.trim());
   if(h)return {kind:'heading',parts:inlineParts(h[1])};
   const bullet=/^\s*[-*]\s+(.+)$/.exec(line);
   if(bullet)return {kind:'bullet',parts:inlineParts(bullet[1])};
   const number=/^\s*(\d+)\.\s+(.+)$/.exec(line);
   if(number)return {kind:'number',number:number[1],parts:inlineParts(number[2])};
   return {kind:'paragraph',parts:inlineParts(line)};
 });
}
module.exports={appendFormat,inlineParts,previewLines};
