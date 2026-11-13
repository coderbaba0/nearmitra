const {test}=require('node:test'),assert=require('node:assert/strict');
const vm=require('node:vm'),fs=require('node:fs');
function browser(){
 const requests=[],timers=new Map(),nodes={chatTypingBar:{style:{}},typingPeerLabel:{}};
 let timerId=0;
 const ctx={console,Blob,ArrayBuffer,NearMitraChat:require('./chat-routing.js'),NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),
 localStorage:{getItem:()=>null,setItem(){}},document:{addEventListener(){},getElementById:id=>nodes[id]||null,querySelectorAll:()=>[]},window:{addEventListener(){}},performance:{now:()=>0},
 setInterval:()=>0,clearInterval(){},setTimeout:fn=>{timers.set(++timerId,fn);return timerId;},clearTimeout:id=>timers.delete(id),
 fetch:async(url,options)=>{requests.push({url,body:JSON.parse(options.body)});return {ok:true};},clock:10000};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);
 const run=code=>vm.runInContext(code,ctx);
 run("Date.now=()=>clock;appState.peers=[{id:'phone',internet_device_id:'wan-phone',ip:'192.168.1.6',name:'Phone'}];appState.activePeer=appState.peers[0]");
 return {ctx,run,requests,timers,nodes};
}
test('Nearby typing refreshes while continuously typing, then sends stop on idle',()=>{
 const b=browser();b.run('handleUserTyping()');
 b.ctx.clock+=500;b.run('handleUserTyping()');assert.equal(b.requests.length,1);
 b.ctx.clock+=1500;b.run('handleUserTyping()');
 assert.equal(b.requests.length,2);assert.ok(b.requests.every(r=>r.body.is_typing));
 [...b.timers.values()].at(-1)();assert.equal(b.requests.at(-1).body.is_typing,false);
});
test('Clearing the input sends stop and switching recipients stops the previous peer',()=>{
 const b=browser();b.run('handleUserTyping();handleUserTyping(false)');
 assert.deepEqual(b.requests.map(r=>r.body.is_typing),[true,false]);
 b.run("handleUserTyping();appState.peers.push({id:'other',ip:'192.168.1.7'});appState.activePeer=appState.peers[1];handleUserTyping()");
 assert.deepEqual(b.requests.slice(-2).map(r=>[r.body.target_ip,r.body.is_typing]),[['192.168.1.6',false],['192.168.1.7',true]]);
});
test('WAN typing survives backend polls and is scoped to the sender conversation',()=>{
 const b=browser();b.run("populateCctvPeerSelect=()=>{};populateAudioPeerSelect=()=>{};renderMasterList=()=>{};setRemotePeerTyping('wan-phone',true);updateUIFromState({typing_peers:[]})");
 assert.equal(b.nodes.chatTypingBar.style.display,'flex');
 b.run("appState.activePeer={id:'unrelated',name:'Other'};renderPeerTyping()");assert.equal(b.nodes.chatTypingBar.style.display,'none');
 b.run("appState.activePeer=appState.peers[0];renderPeerTyping()");assert.equal(b.nodes.chatTypingBar.style.display,'flex');
 b.run("setRemotePeerTyping('wan-phone',false)");assert.equal(b.nodes.chatTypingBar.style.display,'none');
});
test('WAN typing sends start, throttled refresh, and explicit stop to the connected peer',()=>{
 const b=browser();b.ctx.sent=[];
 b.run("appState.peers=[];appState.activePeer={id:'wan-phone'};appState.wanState={internet_mode_enabled:true,trusted_devices:[{id:'wan-phone',is_online:true}]};wanConnectedPeerId='wan-phone';wanDataChannel={readyState:'open',send:data=>sent.push(JSON.parse(data))};handleUserTyping()");
 b.ctx.clock+=500;b.run('handleUserTyping()');assert.equal(b.ctx.sent.length,1);
 b.ctx.clock+=1500;b.run('handleUserTyping();handleUserTyping(false)');
 assert.deepEqual(Array.from(b.ctx.sent,m=>m.payload.isTyping),[true,true,false]);assert.equal(b.requests.length,0);
});
test('Earlier expiry timer cannot hide refreshed typing; stale state expires',()=>{
 const b=browser();b.run("setRemotePeerTyping('phone',true)");const first=[...b.timers.values()][0];
 b.ctx.clock+=2000;b.run("setRemotePeerTyping('phone',true)");b.ctx.clock+=1500;first();assert.equal(b.nodes.chatTypingBar.style.display,'flex');
 b.ctx.clock+=2500;b.run('renderPeerTyping()');assert.equal(b.nodes.chatTypingBar.style.display,'none');
});
test('WAN explicit false is respected by the real incoming handler',async()=>{
 const b=browser();b.ctx.dc={send(){}};b.run("setupWanDataChannel(dc,'wan-phone','Phone')");
 for(const type of ['control','typing']){
  await b.ctx.dc.onmessage({data:JSON.stringify({type,payload:{action:'typing',isTyping:true}})});
  await new Promise(setImmediate);
  assert.equal(b.nodes.chatTypingBar.style.display,'flex');
  await b.ctx.dc.onmessage({data:JSON.stringify({type,payload:{action:'typing',isTyping:false}})});
  await new Promise(setImmediate);
  assert.equal(b.nodes.chatTypingBar.style.display,'none');
 }
});
