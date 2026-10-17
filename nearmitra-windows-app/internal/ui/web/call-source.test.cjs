const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function browser(source='both',denyDisplay=false){
 const events=[],requests=[],elements=new Map();
 const element=(id,value='')=>{const e={value,style:{},classList:{toggle(){},add(){},remove(){}},setAttribute(){}};elements.set(id,e);return e;};
 element('pcAudioSource',source);element('pcMicrophoneDevice');element('callAudioStatus');element('audioPeerSelect','192.168.1.4');
 const track=kind=>({kind,enabled:true,stop(){this.stopped=true;},addEventListener(){}});
 class Stream{constructor(tracks=[]){this.tracks=tracks;}getTracks(){return this.tracks;}getAudioTracks(){return this.tracks.filter(t=>t.kind==='audio');}getVideoTracks(){return this.tracks.filter(t=>t.kind==='video');}}
 class PC{constructor(){this.tracks=[];}addTrack(track){this.tracks.push(track);}getTransceivers(){return this.tracks.map(track=>({sender:{track}}));}addTransceiver(){}close(){}}
 const ctx={console,Response,performance:{now:()=>0},NearMitraChat:require('./chat-routing.js'),NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),MediaStream:Stream,RTCPeerConnection:PC,localStorage:{getItem:()=>null,setItem(){}},document:{addEventListener(){},getElementById:id=>elements.get(id)||null,querySelectorAll:()=>[],createElement:()=>({style:{},setAttribute(){}})},window:{addEventListener(){}},setInterval:()=>1,clearInterval(){},setTimeout:()=>1,clearTimeout(){},
 navigator:{mediaDevices:{async getUserMedia(c){events.push(['mic',c]);return new Stream([...(c.audio?[track('audio')]:[]),...(c.video?[track('video')]:[])]);},async getDisplayMedia(){events.push(['display']);if(denyDisplay)throw new Error('Share tab cancelled');return new Stream([track('audio'),track('video')]);}}},
 fetch:async(path,options)=>{requests.push({path,body:JSON.parse(options.body)});return new Response('{}');}};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);
 vm.runInContext("showToast=message=>{lastToast=message;};switchTab=()=>{};setCallMode=()=>{};appState.peers=[{id:'phone',name:'Phone',ip:'192.168.1.4',is_online:true}];",ctx);
 return {ctx,events,requests,run:code=>vm.runInContext(code,ctx),element};
}
for(const action of ['voice_call','video_call'])test(`${action} sends Nearby invite without Share Tab even with system mixing selected`,async()=>{
 const b=browser('both',true);await b.run(`startSelectedAudioAction('${action}')`);
 assert.equal(b.events.filter(e=>e[0]==='display').length,0);assert.equal(b.events[0][0],'mic');
 const invite=b.requests.find(r=>r.path==='/api/call/invite');assert.ok(invite,'actual app adapter must send invite');assert.equal(invite.body.target_ip,'192.168.1.4');assert.equal(invite.body.is_video,action==='video_call');assert.equal(Boolean(b.events[0][1].video),action==='video_call');await b.run('desktopCall.stop(false)');
});
test('Incoming call answers with microphone without system-share prompt',async()=>{
 const b=browser('system',true);await b.run("desktopCall.accept(appState.peers[0],false)");assert.equal(b.events[0][0],'mic');assert.equal(b.events.length,1);assert.ok(b.requests.some(r=>r.path==='/api/call/answer'));await b.run('desktopCall.stop(false)');
});
test('Explicit system-audio broadcast still requests system capture and sends invite',async()=>{
 const b=browser('system');await b.run("startSelectedAudioAction('broadcast_voice')");assert.equal(b.events[0][0],'display');assert.equal(b.events.length,1);assert.ok(b.requests.some(r=>r.path==='/api/call/invite'));await b.run('desktopCall.stop(false)');
});
test('Cancelled broadcast does not prevent a later normal Nearby call',async()=>{
 const b=browser('system',true);await b.run("startSelectedAudioAction('broadcast_voice')");assert.equal(b.requests.length,0);assert.equal(b.run('desktopCall.session'),null);
 await b.run("startSelectedAudioAction('voice_call')");assert.ok(b.requests.some(r=>r.path==='/api/call/invite'));assert.equal(b.events.filter(e=>e[0]==='display').length,1);await b.run('desktopCall.stop(false)');
});
test('Stale offline presence does not block a selected Nearby IP or depend on WAN aliases',async()=>{
 const b=browser();b.run("appState.peers[0].is_online=false;chatDeviceLinks={phone:'stale-wan'};resolveChatRoute=()=>{throw new Error('call must not use WAN chat routing')}");
 await b.run("startSelectedAudioAction('voice_call')");assert.equal(b.requests.find(r=>r.path==='/api/call/invite')?.body.target_ip,'192.168.1.4');await b.run('desktopCall.stop(false)');
});
test('LAN-only selected device is attempted directly even before UDP peer discovery',async()=>{
 const b=browser();b.run("appState.peers=[];appState.lanDevices=[{ip:'192.168.1.4',hostname:'Phone'}]");
 await b.run("startSelectedAudioAction('video_call')");assert.equal(b.requests.find(r=>r.path==='/api/call/invite')?.body.target_ip,'192.168.1.4');await b.run('desktopCall.stop(false)');
});
test('Selected IP never falls back to a different active device',async()=>{
 const b=browser();b.element('audioPeerSelect','192.168.1.8');b.run("appState.activePeer=appState.peers[0]");await b.run("startSelectedAudioAction('voice_call')");assert.equal(b.requests.find(r=>r.path==='/api/call/invite')?.body.target_ip,'192.168.1.8');await b.run('desktopCall.stop(false)');
});
test('WAN-only target cannot initiate a Nearby call',async()=>{
 const b=browser();await b.run("startCallWithPeer('wan://remote','Internet peer',false)");assert.equal(b.requests.length,0);assert.match(b.ctx.lastToast,/local IP/);
});
test('No PC microphone still sends the actual Nearby invite and identifies local capture limitation',async()=>{
 const b=browser();b.ctx.navigator.mediaDevices.getUserMedia=async()=>{const e=new Error('Requested device not found');e.name='NotFoundError';throw e;};b.ctx.navigator.mediaDevices.enumerateDevices=async()=>[];
 await b.run("startSelectedAudioAction('voice_call')");assert.equal(b.requests.find(r=>r.path==='/api/call/invite')?.body.target_ip,'192.168.1.4');assert.match(b.run('desktopCall.session.mediaWarnings.join()'),/No PC microphone/);await b.run('desktopCall.stop(false)');
});
test('No PC camera does not prevent Nearby video invitation with working microphone',async()=>{
 const b=browser();const original=b.ctx.navigator.mediaDevices.getUserMedia;b.ctx.navigator.mediaDevices.getUserMedia=async c=>{if(c.video){const e=new Error('Requested device not found');e.name='NotFoundError';throw e;}return original(c);};
 await b.run("startSelectedAudioAction('video_call')");assert.equal(b.requests.find(r=>r.path==='/api/call/invite')?.body.is_video,true);assert.match(b.run('desktopCall.session.mediaWarnings.join()'),/No PC camera/);await b.run('desktopCall.stop(false)');
});
