const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function browser(source='both',denyDisplay=false,withWireless=false){
 const events=[],requests=[],elements=new Map();
 const element=(id,value='')=>{const e={value,style:{},classList:{toggle(){},add(){},remove(){},contains(){return false;}},setAttribute(){}};elements.set(id,e);return e;};
 element('wirelessCaptureScope','tab');element('pcAudioSource',source);element('pcMicrophoneDevice');element('callAudioStatus');element('audioPeerSelect','192.168.1.4');
 const track=kind=>({kind,enabled:true,stop(){this.stopped=true;},addEventListener(){}});
 class Stream{constructor(tracks=[]){this.tracks=tracks;}getTracks(){return this.tracks;}getAudioTracks(){return this.tracks.filter(t=>t.kind==='audio');}getVideoTracks(){return this.tracks.filter(t=>t.kind==='video');}addTrack(track){this.tracks.push(track);}}
 class PC{constructor(){this.tracks=[];this.transceivers=[];}addTrack(track){this.tracks.push(track);this.transceivers.push({sender:{track}});}getTransceivers(){return this.transceivers;}addTransceiver(kind,options){const tx={sender:{track:typeof kind==='string'?null:kind,async replaceTrack(track){this.track=track;}},currentDirection:'sendrecv',...options};this.transceivers.push(tx);return tx;}async createOffer(){return {type:'offer',sdp:'PC audio'};}async createAnswer(){return {type:'answer',sdp:'PC answer'};}async setLocalDescription(d){this.localDescription=d;}async setRemoteDescription(d){this.remoteDescription=d;}async addIceCandidate(){}close(){}}
 const ctx={NearMitraTransfers:require('./chat-transfers.js'),NearMitraWirelessAudio:withWireless?require('./wireless-audio.js'):undefined,crypto:{randomUUID:()=> '12345678-abcd'},console,Response,performance:{now:()=>0},NearMitraChat:require('./chat-routing.js'),NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),MediaStream:Stream,RTCPeerConnection:PC,localStorage:{getItem:()=>null,setItem(){}},document:{addEventListener(){},getElementById:id=>elements.get(id)||null,querySelectorAll:()=>[],createElement:()=>({style:{},setAttribute(){}})},window:{addEventListener(){}},setInterval:()=>1,clearInterval(){},setTimeout:()=>1,clearTimeout(){},
 navigator:{mediaDevices:{async getUserMedia(c){events.push(['mic',c]);return new Stream([...(c.audio?[track('audio')]:[]),...(c.video?[track('video')]:[])]);},async getDisplayMedia(){events.push(['display']);if(denyDisplay)throw new Error('Share tab cancelled');return new Stream([track('audio'),track('video')]);}}},
 fetch:async(path,options)=>{requests.push({path,body:options?.body?JSON.parse(options.body):null});return new Response('{}');}};
 vm.createContext(ctx);
 if(withWireless==='page'){
  for(const key of ['NearMitraWirelessAudio','NearMitraAudioCapture','NearMitraCall','NearMitraChat'])delete ctx[key];
  const html=fs.readFileSync(__dirname+'/index.html','utf8');
  for(const match of html.matchAll(/<script src="([^"]+)"/g))vm.runInContext(fs.readFileSync(__dirname+'/'+match[1],'utf8'),ctx,{filename:match[1]});
 }else vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);
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

test('Connected Windows call adapter shares display without requesting camera and restores audio-only view',async()=>{
 const b=browser('mic');await b.run("startSelectedAudioAction('voice_call')");
 b.run("desktopCall.session.pc.connectionState='connected';desktopCall.session.pc.onconnectionstatechange()");
 await b.run('toggleScreenShare()');assert.equal(b.events.filter(e=>e[0]==='display').length,1);assert.equal(b.events.filter(e=>e[0]==='mic').length,1);
 assert.equal(b.run('desktopCall.session.sharing'),true);assert.equal(b.run('desktopCall.session.video'),false);
 await b.run('toggleScreenShare()');assert.equal(b.run('desktopCall.session.sharing'),false);assert.equal(b.requests.at(-1).body.is_video,false);
 await b.run('toggleVideoCamera()');assert.equal(b.run('desktopCall.session.video'),true);assert.equal(b.events.at(-1)[1].audio,false);
 await b.run('toggleVideoCamera()');assert.equal(b.run('desktopCall.session.video'),false);await b.run('desktopCall.stop(false)');
});

test('Voice broadcast uses the shared audio source and target without starting a call',async()=>{
 const b=browser('system',false,true);
 await b.run('startWirelessPcAudio()');
 assert.equal(b.events[0][0],'display');assert.equal(b.events.filter(e=>e[0]==='mic').length,0);
 const offer=b.requests.find(r=>r.body.type==='wireless_audio_offer');assert.ok(offer);assert.equal(offer.body.audio_mode,'system');assert.equal(offer.body.target_ip,'192.168.1.4');assert.equal(offer.body.session_id,'wa-12345678-abcd');
 assert.ok(!b.requests.some(r=>r.path.startsWith('/api/call/')));assert.equal(b.run('desktopCall.session'),null);
 await b.run('wirelessAudio.stop(false)');
});
test('Standalone phone microphone adapter sends an explicit request without opening any PC capture',async()=>{
 const b=browser('both',false,true);await b.run('requestWirelessPhoneMic()');
 assert.equal(b.events.length,0);assert.equal(b.requests[0].body.type,'wireless_audio_request');assert.equal(b.requests[0].body.audio_mode,'mic');assert.equal(b.run('desktopCall.session'),null);
 await b.run('wirelessAudio.stop(false)');
});

test('Wireless controls appear in Voice broadcast and are absent from CCTV; selectors are shared',()=>{
 const html=fs.readFileSync(__dirname+'/index.html','utf8');
 const cctv=html.slice(html.indexOf('<section id="tab-cctv"'),html.indexOf('<section id="tab-voice"'));
 const voice=html.slice(html.indexOf('<section id="tab-voice"'),html.indexOf('<section id="tab-ai"'));
 assert.ok(!cctv.includes('wirelessAudio'));assert.match(voice,/id="wirelessAudioSend"[^>]*onclick="startWirelessPcAudio\(\)"/);
 assert.match(voice,/id="wirelessAudioMic"[^>]*onclick="requestWirelessPhoneMic\(\)"/);
 assert.match(voice,/id="wirelessAudioPanel"/);assert.ok(!html.includes('id="wirelessAudioPeerSelect"'));assert.ok(!html.includes('id="wirelessAudioSource"'));
 assert.equal((html.match(/id="audioPeerSelect"/g)||[]).length,1);assert.equal((html.match(/id="pcAudioSource"/g)||[]).length,1);
 assert.match(fs.readFileSync(__dirname+'/style.css','utf8'),/#wirelessAudioPanel \[hidden\]\s*\{display:none !important;/);
});
test('Wireless source uses the selected PC microphone and never a different active device',async()=>{
 const b=browser('mic',false,true);b.element('pcMicrophoneDevice','chosen-mic');b.element('audioPeerSelect','192.168.1.8');
 b.run('appState.activePeer=appState.peers[0]');await b.run('startWirelessPcAudio()');
 assert.equal(b.events[0][1].audio.deviceId.exact,'chosen-mic');assert.equal(b.requests.find(r=>r.body.type==='wireless_audio_offer').body.target_ip,'192.168.1.8');
 await b.run('wirelessAudio.stop(false)');
});
test('Shared target/source lock for an active stream, idle controls stay hidden, and Stop restores selectors',async()=>{
 const b=browser('system',false,true);
 for(const id of ['wirelessAudioStop','wirelessAudioMute','wirelessAudioPlay','wirelessAudioConsent','wirelessAudioVolumeControl'])b.element(id);
 b.run('renderWirelessAudio()');
 assert.equal(b.run("document.getElementById('wirelessAudioMute').hidden"),true);
 assert.equal(b.run("document.getElementById('wirelessAudioPlay').hidden"),true);
 await b.run('startWirelessPcAudio()');assert.equal(b.run("document.getElementById('audioPeerSelect').disabled"),true);assert.equal(b.run("document.getElementById('pcAudioSource').disabled"),true);
 await b.run('wirelessAudio.stop(false)');assert.equal(b.run("document.getElementById('audioPeerSelect').disabled"),false);assert.equal(b.run("document.getElementById('pcAudioSource').disabled"),false);
});
test('Incoming wireless approval navigates to Voice without touching CCTV',async()=>{
 const b=browser('system',false,true);b.run("window.openedTab='';switchTab=tab=>window.openedTab=tab");
 await b.run("wirelessAudio.handle('192.168.1.4',{type:'wireless_audio_request',session_id:'wa-12345678-abcd',audio_mode:'system',sender:'Phone'})");
 assert.equal(b.run('window.openedTab'),'voice');assert.equal(b.events.length,0);await b.run('wirelessAudio.stop(false)');
});
test('Selected wireless target survives a missing discovery poll without switching device',async()=>{
 const b=browser('system',false,true);b.run("populateAudioPeerSelect();appState.peers=[];appState.lanDevices=[];appState.activePeer={ip:'192.168.1.99'};populateAudioPeerSelect()");
 assert.match(b.run("document.getElementById('audioPeerSelect').innerHTML"),/192\.168\.1\.4/);
 await b.run('startWirelessPcAudio()');assert.equal(b.requests.at(-1).body.target_ip,'192.168.1.4');await b.run('wirelessAudio.stop(false)');
});

test('Installed page script order initializes the wireless service without module injection',async()=>{
 const b=browser('system',false,'page');assert.ok(b.run('wirelessAudio'));assert.ok(b.run('wirelessAudioCapture'));
 await b.run('startWirelessPcAudio()');assert.equal(b.events[0][0],'display');assert.equal(b.requests.at(-1).body.type,'wireless_audio_offer');await b.run('wirelessAudio.stop(false)');
});
test('Page-loaded engine shows approval for a real phone request envelope',async()=>{
 const b=browser('system',false,'page');const consent=b.element('wirelessAudioConsent');b.element('wirelessAudioStatus');
 await b.run("handleIncomingStreamSignal({peer_ip:'192.168.1.4',header:{type:'wireless_audio_request',session_id:'wa-12345678-abcd',audio_mode:'system',sender:'Phone'}})");
 assert.equal(consent.hidden,false);assert.equal(b.events.length,0);assert.equal(b.requests.at(-1).body.type,'wireless_audio_pending');
 await b.run('wirelessAudio.approve()');assert.equal(b.events[0][0],'display');assert.equal(b.requests.at(-1).body.type,'wireless_audio_offer');await b.run('wirelessAudio.stop(false)');
});
test('Missing wireless script gives a recovery message instead of a null start error',async()=>{
 const b=browser('system',false,false);const status=b.element('wirelessAudioStatus'),send=b.element('wirelessAudioConnect'),stop=b.element('wirelessAudioStop');
 b.run('renderWirelessAudio()');assert.equal(send.disabled,true);assert.equal(stop.hidden,true);assert.match(status.innerText,/did not load/);
 await b.run('startWirelessPcAudio()');assert.match(b.run('lastToast'),/install the latest setup/);assert.equal(b.requests.length,0);
});
test('All-PC broadcast uses the Windows output selector without any browser Share Tab request',async()=>{
 const b=browser('system',false,'page');b.element('wirelessOutputDevice','realtek-output');
 b.run("document.getElementById('wirelessCaptureScope').value='system';nativeSystemAudio.capture=async device=>{window.nativeDevice=device;return new MediaStream([{kind:'audio',enabled:true,stop(){},addEventListener(){}}]);};nativeSystemAudio.release=()=>{}");
 await b.run('startWirelessPcAudio()');assert.equal(b.run('window.nativeDevice'),'realtek-output');assert.equal(b.events.length,0);assert.equal(b.requests.at(-1).body.type,'wireless_audio_offer');await b.run('wirelessAudio.stop(false)');
});

test('Unread badge counts one item per incoming transfer, keeps count on completion and clears only for visible sender chat',()=>{
 const b=browser();const badge=b.element('badgeChatUnread');const pane=b.element('tab-chat');
 b.run("appState.messages=[];appState.transfers=[];syncIncomingIndicators(true);appState.transfers=[{ID:'a',PeerID:'phone',PeerIP:'192.168.1.4',PeerName:'Phone',Direction:'download',Active:true,BytesSent:10,BytesTotal:100,FileName:'movie.mp4'}];syncIncomingIndicators()");
 assert.equal(badge.innerText,'1');assert.equal(badge.hidden,false);assert.match(b.run("incomingDeviceBadge({id:'phone',ip:'192.168.1.4'})"),/device-unread-count/);
 b.run('appState.transfers[0].BytesSent=50;syncIncomingIndicators()');assert.equal(badge.innerText,'1');
 b.run("appState.messages=[{id:'a',peer_id:'phone',peer_ip:'192.168.1.4',mine:false}];syncIncomingIndicators()");assert.equal(badge.innerText,'1');
 pane.classList.contains=()=>true;b.ctx.document.hasFocus=()=>true;
 b.run("appState.activePeer={id:'different',ip:'192.168.1.7'};syncIncomingIndicators()");assert.equal(badge.innerText,'1');
 b.run("appState.activePeer=appState.peers[0];syncIncomingIndicators()");assert.equal(badge.hidden,true);
});
test('Live Nearby file renders in the actual sender chat with progress speed and ETA before completion',()=>{
 const b=browser(),chat=b.element('chatStream');b.run("appState.activePeer=appState.peers[0];appState.messages=[];appState.transfers=[{ID:'live1',PeerID:'phone',PeerIP:'192.168.1.4',PeerName:'Phone',Direction:'download',Active:true,BytesSent:500,BytesTotal:1000,SpeedMBps:1.2,ETASeconds:3,FileName:'incoming.pdf',StartTime:new Date().toISOString()}];renderChatMessages()");
 assert.match(chat.innerHTML,/incoming.pdf/);assert.match(chat.innerHTML,/Receiving \(50%\)/);assert.match(chat.innerHTML,/1.2 MB\/s.*ETA 3s/);
 b.run("appState.activePeer={id:'other',ip:'192.168.1.8',name:'Other'};renderChatMessages()");assert.ok(!chat.innerHTML.includes('incoming.pdf'));
});
