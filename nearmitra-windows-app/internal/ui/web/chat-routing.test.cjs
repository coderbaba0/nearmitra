const {test}=require('node:test'),assert=require('node:assert/strict'),chat=require('./chat-routing.js');
const peers=[{id:'lan',internet_device_id:'wan',name:'Phone',ip:'192.168.1.4',is_online:true}];
const wan={internet_mode_enabled:true,trusted_devices:[{id:'wan',is_online:true}]},links=chat.learn(peers,{});
test('Both entry points prioritize Nearby and show both histories',()=>{for(const p of [peers[0],{id:'wan',is_wan:true}]){assert.equal(chat.resolve(p,peers,wan,links).mode,'nearby');assert.ok(chat.matches({peer_id:'lan'},p,peers,links));assert.ok(chat.matches({peer_id:'wan',is_wan:true},p,peers,links));assert.ok(!chat.matches({peer_id:'unrelated'},p,peers,links));}});
test('WAN requires explicit enablement and a trusted recipient',()=>{assert.equal(chat.resolve({id:'wan'},[],wan,links).mode,'wan');assert.equal(chat.resolve({id:'wan'},[],{...wan,internet_mode_enabled:false},links).mode,'offline');assert.equal(chat.resolve({id:'untrusted'},[],wan,links).mode,'offline');});
test('Received native folders render as attachments and updated status replaces same ID',()=>{const m=chat.merge([{id:'f1',status:'Downloading',at:'2026-01-01'}],[{id:'f1',kind:'folder',file_name:'Documents',file_path:'C:/Received/Documents',status:'Delivered',at:'2026-01-01'}]);assert.equal(m.length,1);assert.equal(m[0].attachment.name,'Documents');assert.equal(m[0].status,'Delivered');assert.ok(m[0].file_path);});
test('Queued messages survive unrelated server snapshots',()=>{assert.equal(chat.merge([{id:'q',status:'Queued'}],[]).length,1);});
const vm=require('node:vm'),fs=require('node:fs');
function browser(fetcher){
 const ctx={console,NearMitraChat:chat,NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),localStorage:{getItem:()=>null,setItem:()=>{}},document:{addEventListener:()=>{},getElementById:()=>null,querySelectorAll:()=>[]},window:{addEventListener:()=>{}},performance:{now:()=>0},setInterval:()=>0,clearInterval:()=>{},setTimeout,clearTimeout,Blob,FormData,File,ArrayBuffer,Uint8Array,URL,fetch:fetcher,crypto:require('node:crypto').webcrypto};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);vm.runInContext('showToast=()=>{};',ctx);return ctx;
}
async function settle(){for(let i=0;i<8;i++) await new Promise(setImmediate);}
test('Real WAN handler persists mobile file bytes before acknowledging delivery',async()=>{
 let stored=false;const ctx=browser(async(url,options)=>{assert.equal(url,'/api/chat/receive-file');const meta=JSON.parse(options.body.get('message'));assert.equal(await options.body.get('file').text(),'hello');stored=true;return new Response(JSON.stringify({...meta,file_path:'C:/Received/mobile.txt',status:'Delivered'}));});
 const ack=[];const dc={send:msg=>{const m=JSON.parse(msg);if(m.type==='delivery_ack'){assert.ok(stored);ack.push(m);}}};ctx.dc=dc;
 vm.runInContext("setupWanDataChannel(dc,'mobile-wan','Phone')",ctx);
 dc.onmessage({data:JSON.stringify({type:'fileMeta',payload:{transferId:'f1',fileName:'mobile.txt',fileSize:5}})});
 dc.onmessage({data:new TextEncoder().encode('hello').buffer});
 dc.onmessage({data:JSON.stringify({type:'fileEnd',payload:{transferId:'f1'}})});
 await settle();assert.equal(ack[0]?.status,'delivered');assert.equal(vm.runInContext('appState.messages[0].file_path',ctx),'C:/Received/mobile.txt');
});
test('Real WAN handler rejects incomplete bytes instead of showing success',async()=>{
 let requested=false;const ctx=browser(async()=>{requested=true;throw new Error('unexpected save');});const ack=[];ctx.dc={send:msg=>ack.push(JSON.parse(msg))};vm.runInContext("setupWanDataChannel(dc,'mobile-wan','Phone')",ctx);
 ctx.dc.onmessage({data:JSON.stringify({type:'fileMeta',payload:{transferId:'f1',fileName:'file',fileSize:100}})});ctx.dc.onmessage({data:new ArrayBuffer(3)});ctx.dc.onmessage({data:JSON.stringify({type:'fileEnd'})});await settle();assert.equal(requested,false);assert.equal(ack[0]?.status,'failed');assert.equal(vm.runInContext('appState.messages[0].status',ctx),'Failed');
});

test('Remote and local reactions merge independently and clear on the next server snapshot',()=>{
 let merged=chat.merge([{id:'m',reaction:'❤️',local_reaction:'👍'}],[{id:'m',reaction:'❤️',local_reaction:'👍'}]);
 assert.deepEqual(chat.normalize(merged[0]).reactions,{'❤️':1,'👍':1});
 merged=chat.merge(merged,[{id:'m'}]);assert.deepEqual(chat.normalize(merged[0]).reactions,{});
 assert.deepEqual(chat.normalize({reaction:'❤️',local_reaction:'❤️'}).reactions,{'❤️':2});
});
test('Reply aliases normalize and escape correctly in actual chat rendering',()=>{
 const ctx=browser();const stream={innerHTML:'',scrollHeight:100,scrollTop:0,clientHeight:100};
 ctx.document.getElementById=id=>id==='chatStream'?stream:null;
 vm.runInContext("syncIncomingIndicators=()=>{};appState.peers=[{id:'phone',ip:'192.168.1.6',name:'Phone'}];appState.activePeer=appState.peers[0];appState.messages=[{id:'quoted',peer_id:'phone',text:'Yes',sender:'Phone',at:new Date(),reaction:'❤️',replyToId:'original',replyToSender:'PC',replyToText:'<img onerror=evil()>',isForwarded:true}];renderChatMessages()",ctx);
 assert.match(stream.innerHTML,/msg-quoted-reply/);assert.match(stream.innerHTML,/data-quote-id="original"/);assert.match(stream.innerHTML,/&lt;img onerror=evil\(\)&gt;/);assert.ok(!stream.innerHTML.includes('<img'));assert.match(stream.innerHTML,/❤️/);assert.match(stream.innerHTML,/Forwarded/);assert.match(stream.innerHTML,/Select/);
});
test('Desktop reply sends quote metadata and resets the composer snapshot',()=>{
 const ctx=browser();ctx.input={value:'Reply'};ctx.document.getElementById=id=>id==='chatInput'?ctx.input:null;
 vm.runInContext("renderChatMessages=()=>{};handleUserTyping=()=>{};flushChatOutbox=()=>{};appState.peers=[{id:'phone',ip:'192.168.1.6'}];appState.activePeer=appState.peers[0];chatReply={id:'old',sender:'Phone',text:'Question'};sendChatMessage()",ctx);
 const m=vm.runInContext('appState.messages[0]',ctx);assert.equal(m.reply_to_id,'old');assert.equal(m.reply_to_text,'Question');assert.equal(vm.runInContext('chatReply',ctx),null);
});
test('Removing own Nearby reaction sends an explicit empty emoji and keeps remote heart',async()=>{
 let sent;const ctx=browser(async(url,options)=>{assert.equal(url,'/api/chat/react');sent=JSON.parse(options.body);return new Response('');});
 vm.runInContext("appState.peers=[{id:'phone',ip:'192.168.1.6'}];appState.activePeer=appState.peers[0];appState.messages=[{id:'m',peer_id:'phone',reaction:'❤️',local_reaction:'👍'}]",ctx);
 await vm.runInContext("toggleMessageReaction('m','👍')",ctx);assert.equal(sent.emoji,'');assert.equal(sent.target_ip,'192.168.1.6');
 assert.deepEqual(chat.normalize(vm.runInContext('appState.messages[0]',ctx)).reactions,{'❤️':1});
});
test('WAN control reactions persist for their peer, including removal',async()=>{
 const requests=[];const ctx=browser(async(url,options)=>{requests.push(JSON.parse(options.body));return new Response('');});ctx.dc={send(){}};
 vm.runInContext("appState.messages=[{id:'m',peer_id:'phone',reaction:''}];setupWanDataChannel(dc,'phone','Phone')",ctx);
 for(const emoji of ['❤️','❤️','']) {ctx.dc.onmessage({data:JSON.stringify({type:'control',payload:{action:'reaction',messageId:'m',reaction:emoji}})});await settle();}
 assert.equal(requests.length,3);assert.equal(requests[0].emoji,'❤️');assert.equal(requests[1].emoji,'❤️');assert.equal(requests[2].emoji,'');assert.equal(requests[2].incoming,true);assert.equal(requests[2].peer_id,'phone');
});
test('Mobile WAN reply carries its original quote into persistence',async()=>{
 let stored;const ctx=browser(async(url,options)=>{stored=JSON.parse(options.body);return new Response('{}');});ctx.dc={send(){}};vm.runInContext("setupWanDataChannel(dc,'phone','Phone')",ctx);
 ctx.dc.onmessage({data:JSON.stringify({id:'reply',type:'text',payload:{text:'Yes',replyToId:'q',replyToSender:'PC',replyToText:'Ready?'}})});await settle();assert.equal(stored.reply_to_id,'q');assert.equal(stored.reply_to_text,'Ready?');
});
test('Nearby forwarding uses stored message IDs and the canonical recipient',async()=>{
 let sent;const ctx=browser(async(url,options)=>{assert.equal(url,'/api/chat/forward');sent=JSON.parse(options.body);return new Response(JSON.stringify({id:'new',peer_id:'phone',text:'Hi',is_forwarded:true,status:'Sent'}));});
 vm.runInContext("appState.peers=[{id:'phone',ip:'192.168.1.6'}]",ctx);
 await vm.runInContext("forwardChatMessage({id:'original',text:'Hi',reply_to_id:'private-quote'},appState.peers[0])",ctx);
 assert.deepEqual(sent,{id:'original',peer_id:'phone'});assert.equal(vm.runInContext('appState.messages[0].is_forwarded',ctx),true);
});
test('Forward errors stay errors instead of appending a successful chat message',async()=>{
 const ctx=browser(async()=>new Response('Original file is no longer available',{status:404}));vm.runInContext("appState.peers=[{id:'phone',ip:'192.168.1.6'}]",ctx);
 await assert.rejects(vm.runInContext("forwardChatMessage({id:'missing',kind:'file'},appState.peers[0])",ctx),/no longer available/);assert.equal(vm.runInContext('appState.messages.length',ctx),0);
});
test('WAN file forwarding uses saved bytes and preserves folder and forwarded flags',async()=>{
 const ctx=browser(async()=>new Response('archive bytes'));ctx.sent=[];
 vm.runInContext("appState.wanState={internet_mode_enabled:true,trusted_devices:[{id:'phone',is_online:true}]};streamFileOverWanInternal=async(file,id,name,folder,meta)=>{sent.push({file,id,folder,meta});return {status:'Sent'}}",ctx);
 await vm.runInContext("forwardChatMessage({id:'folder',kind:'folder',file_name:'Docs',file_path:'C:/Received/Docs'}, {id:'phone',name:'Phone'})",ctx);
 assert.equal(ctx.sent[0].file.name,'Docs.zip');assert.equal(await ctx.sent[0].file.text(),'archive bytes');assert.equal(ctx.sent[0].folder,true);assert.equal(ctx.sent[0].meta.is_forwarded,true);
});
test('Selection survives polling and clears when switching to another conversation',()=>{
 const ctx=browser();const stream={innerHTML:'',scrollHeight:100,scrollTop:0,clientHeight:100};ctx.document.getElementById=id=>id==='chatStream'?stream:null;
 vm.runInContext("syncIncomingIndicators=()=>{};appState.peers=[{id:'one',ip:'192.168.1.6'},{id:'two',ip:'192.168.1.7'}];appState.activePeer=appState.peers[0];appState.messages=[{id:'m',peer_id:'one',text:'hello',at:new Date()}];renderChatMessages();chatSelection.add('m');renderChatMessages()",ctx);
 assert.match(stream.innerHTML,/1 selected/);assert.match(stream.innerHTML,/msg-selected/);
 vm.runInContext('renderChatMessages()',ctx);assert.equal(vm.runInContext('chatSelection.size',ctx),1);
 vm.runInContext('appState.activePeer=appState.peers[1];renderChatMessages()',ctx);assert.equal(vm.runInContext('chatSelection.size',ctx),0);assert.ok(!stream.innerHTML.includes('1 selected'));
});
test('Native file responses reuse the wire ID without duplicate bubbles and retain forwarding paths',()=>{
 const ctx=browser();ctx.response={message:{id:'wire-id',peer_id:'phone',kind:'file',file_name:'report.pdf',file_size:2048,file_path:'C:/Reports/report.pdf',mine:true,status:'Sent'}};
 vm.runInContext('acceptSentAttachment(response);acceptSentAttachment(response)',ctx);
 assert.equal(vm.runInContext('appState.messages.length',ctx),1);assert.equal(vm.runInContext('appState.messages[0].id',ctx),'wire-id');assert.equal(vm.runInContext('appState.messages[0].file_path',ctx),'C:/Reports/report.pdf');
 assert.equal(chat.normalize({file_name:'file',status:'Sending'}).attachment.progress,0);
});
test('Folder actions encode literal paths and show backend errors instead of success',async()=>{
 const requests=[];const ctx=browser(async(url)=>{requests.push(url);return new Response('Item is no longer available',{status:500});});ctx.errors=[];vm.runInContext('showToast=message=>errors.push(message)',ctx);
 ctx.path="C:\\Users\\O'Brien\\नया folder\\report #1.pdf";
 await vm.runInContext('showInFolder(path);',ctx);await vm.runInContext('openSaveDirectory()',ctx);
 assert.equal(requests[0],'/api/recents/show-in-folder?path='+encodeURIComponent(ctx.path));assert.equal(requests[1],'/api/open-save-dir');assert.equal(ctx.errors.length,2);assert.match(ctx.errors[0],/no longer available/);
});
