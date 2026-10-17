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
