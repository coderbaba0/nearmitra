const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function browser(fetcher){
 const nodes={aiChatStream:{innerHTML:'',scrollHeight:100},aiChatInput:{value:'Hello'},nearbyAISend:{},nearbyAIStop:{},nearbyAITargetLabel:{},nearbyAITargetStatus:{},aiSubtabProviderBadge:{}};
 const ctx={console,NearMitraChat:require('./chat-routing.js'),NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),localStorage:{getItem:()=>null,setItem(){}},document:{addEventListener(){},getElementById:id=>nodes[id] || null,querySelectorAll:()=>[]},window:{addEventListener(){}},setInterval:()=>0,clearInterval(){},setTimeout,clearTimeout,performance:{now:()=>0},fetch:fetcher,AbortController,TextDecoder,Uint8Array,crypto:require('node:crypto').webcrypto};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);
 vm.runInContext("showToast=()=>{};loadSelectedAISharing=async()=>{};appState.peers=[{id:'phone',name:'Phone',ip:'192.168.1.6'},{id:'other',name:'Other phone',ip:'192.168.1.7'}];appState.activePeer=appState.peers[0]",ctx);
 return {ctx,nodes};
}
test('Nearby AI queries selected device and renders genuine streamed chunks',async()=>{
 let sent;const {ctx,nodes}=browser(async(url,options)=>{assert.equal(url,'/api/ai/nearby-query');sent=JSON.parse(options.body);return new Response('{"reply":"Hello ","done":false}\n{"reply":"from phone","done":false}\n{"status":"done","done":true}\n');});
 await vm.runInContext('sendAIChatMessage()',ctx);
 assert.deepEqual(sent,{peer_id:'phone',prompt:'Hello'});assert.match(nodes.aiChatStream.innerHTML,/Hello from phone/);assert.match(nodes.nearbyAITargetLabel.textContent,/Phone/);assert.equal(nodes.aiSubtabProviderBadge.textContent,'Device');
});
test('Denied remote AI shows owner permission reason and never queries local engine',async()=>{
 const calls=[];const {ctx,nodes}=browser(async(url)=>{calls.push(url);return new Response('{"status":"disabled","reply":"Owner has not allowed this PC","done":true}\n');});await vm.runInContext('sendAIChatMessage()',ctx);
 assert.deepEqual(calls,['/api/ai/nearby-query']);assert.match(nodes.aiChatStream.innerHTML,/Owner has not allowed this PC/);assert.match(nodes.aiChatStream.innerHTML,/Request failed/);
});
test('Switching peer aborts request and separates device AI conversations',async()=>{
 let release;const {ctx,nodes}=browser(async(url,options)=>new Promise((resolve,reject)=>{release=resolve;options.signal.addEventListener('abort',()=>reject(Object.assign(new Error('aborted'),{name:'AbortError'})));}));
 const pending=vm.runInContext('sendAIChatMessage()',ctx);
 vm.runInContext('appState.activePeer=appState.peers[1];syncNearbyAIConversation()',ctx);await pending;
 assert.ok(!nodes.aiChatStream.innerHTML.includes('Hello'));assert.equal(vm.runInContext('nearbyAIRequest',ctx),null);
 vm.runInContext('appState.activePeer=appState.peers[0];syncNearbyAIConversation()',ctx);assert.match(nodes.aiChatStream.innerHTML,/Hello/);
});
test('Nearby AI provider controls cannot reconfigure owner AI',()=>{
 const html=fs.readFileSync(__dirname+'/index.html','utf8');const area=html.slice(html.indexOf('id="chatViewAI"'),html.indexOf('<!-- TAB PANE 2'));
 assert.ok(!area.includes('setAIChatProvider'));assert.match(area,/Share my AI with this device/);assert.match(area,/My AI settings/);
});
test('Explicitly allowing selected phone enables sharing and grants only that device',async()=>{
 const calls=[];const {ctx}=browser(async(url,options)=>{calls.push([url,JSON.parse(options.body)]);return new Response('{}');});
 vm.runInContext("nearbyAISharing={allowed:false,sharing_enabled:false,ai_enabled:true};",ctx);
 await vm.runInContext('toggleSelectedAISharing()',ctx);
 assert.deepEqual(calls,[['/api/ai/share-toggle',{enabled:true}],['/api/ai/peer-permission',{peer_id:'phone',allow:true}]]);
});
