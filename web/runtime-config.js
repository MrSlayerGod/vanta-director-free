// Server-configured limits and default key hints. No polling or DOM observer.
(()=>{
 const originals=new Map();
 function hint(node,key,text){let values=originals.get(node);if(!values){values={};originals.set(node,values);}if(!(key in values))values[key]=text;return values[key];}
 window.addEventListener('message',event=>{
  if(event.data?.action!=='runtimeConfig')return;
  const c=event.data.config||{};window.VantaRuntimeConfig=c;
  const duration=document.getElementById('duration');duration.min=c.minimumDuration;duration.max=c.maximumDuration;
  const record=document.getElementById('motionRecordSeconds');record.max=c.recordingMaximumSeconds;record.value=Math.min(Number(record.value)||20,c.recordingMaximumSeconds);
  document.getElementById('collaborationPanel').hidden=c.collaborationEnabled===false;
  const replace=text=>text.replace(/\b(F9|F10|F11)\b/g,key=>({F9:c.stopTakeKey,F10:c.stopRecordingKey,F11:c.cancelRecordingKey})[key]||key);
  const walker=document.createTreeWalker(document.getElementById('root')||document.body,NodeFilter.SHOW_TEXT);
  let node;while((node=walker.nextNode())){if(['SCRIPT','STYLE'].includes(node.parentElement?.tagName))continue;if(/\bF(?:9|10|11)\b/.test(node.textContent)||originals.has(node))node.textContent=replace(hint(node,'text',node.textContent));}
  for(const el of document.querySelectorAll('[title]')){const title=el.getAttribute('title');if(/\bF(?:9|10|11)\b/.test(title)||originals.get(el)?.title)el.setAttribute('title',replace(hint(el,'title',title)));}
 });
})();
