const {test}=require('node:test'),assert=require('node:assert/strict'),Call=require('./nearby-call.js');
function setup(options={}) {
 const events=[],signals=[],timers=new Set();
 const tracks=[{kind:'audio',enabled:true,stop(){this.stopped=true;}}];
 const stream={getTracks:()=>tracks,getAudioTracks:()=>tracks.filter(t=>t.kind==='audio'),getVideoTracks:()=>tracks.filter(t=>t.kind==='video'),addTrack:t=>tracks.push(t)};
 const transceivers=[];
 const sender=track=>({track,async replaceTrack(value){this.track=value;}});
 const pc={signalingState:'stable',connectionState:'new',candidates:[],tracks:[],transceivers,
 addTrack(t){this.tracks.push(t);const tx={sender:sender(t),direction:'sendrecv'};transceivers.push(tx);return tx.sender;},
 addTransceiver(kind,options){const tx={kind:typeof kind==='string'?kind:kind.kind,sender:sender(typeof kind==='string'?null:kind),currentDirection:'sendrecv',...options};transceivers.push(tx);this.transceiver=tx;return tx;},
 getTransceivers(){return transceivers;},
 async createOffer(options){this.offerOptions=options;this.offers=(this.offers||0)+1;return {type:'offer',sdp:'desktop-offer'};},async createAnswer(){return {type:'answer',sdp:'desktop-answer'};},async setLocalDescription(sdp){this.localDescription=sdp;this.signalingState=sdp.type==='offer'?'have-local-offer':'stable';},async setRemoteDescription(sdp){this.remoteDescription=sdp;this.signalingState=sdp.type==='offer'?'have-remote-offer':'stable';},async addIceCandidate(c){this.candidates.push(c);},close(){this.closed=true;}};
 const call=new Call({createPeerConnection:()=>pc,createStream:(tracks=[])=>({getTracks:()=>tracks,getAudioTracks:()=>tracks.filter(t=>t.kind==='audio'),getVideoTracks:()=>tracks.filter(t=>t.kind==='video'),addTrack:track=>tracks.push(track)}),getUserMedia:async c=>{events.push(['media',c]);return stream;},invite:async()=>events.push(['invite']),answer:async()=>events.push(['answer']),end:async()=>events.push(['end']),sendSignal:async(ip,h)=>signals.push({ip,...h}),onState:state=>events.push(['state',state]),setTimeout:fn=>{timers.add(fn);return fn;},clearTimeout:fn=>timers.delete(fn),...options});
 return {call,pc,stream,tracks,signals,events,timers};
}
const peer={id:'phone',ip:'192.0.2.2',name:'Phone'};
test('Caller gets media before invite; acceptance creates one offer and queues early ICE',async()=>{
 const f=setup();await f.call.start(peer,false);assert.ok(f.events.findIndex(e=>e[0]==='media')<f.events.findIndex(e=>e[0]==='invite'));
 assert.equal(f.pc.offers,undefined);await f.call.handle(peer.ip,{type:'webrtc_ice',candidate:'early',sdp_mline_index:0});
 await f.call.handle(peer.ip,{type:'call_accepted'});await f.call.handle(peer.ip,{type:'call_accepted'});assert.equal(f.pc.offers,1);assert.equal(f.signals[0].type,'webrtc_offer');
 await f.call.handle(peer.ip,{type:'webrtc_answer',sdp:'phone-answer'});assert.equal(f.pc.candidates[0].candidate,'early');
 f.pc.connectionState='connected';f.pc.onconnectionstatechange();assert.equal(f.timers.size,0);
 f.call.mute(true);assert.equal(f.tracks[0].enabled,false);await f.call.stop();assert.ok(f.tracks[0].stopped);assert.ok(f.pc.closed);
});
test('Incoming call answers mobile offer and remote end never echoes an end packet',async()=>{
 const f=setup();await f.call.accept(peer,true);assert.ok(f.events.some(e=>e[0]==='answer'));
 await f.call.handle(peer.ip,{type:'webrtc_offer',sdp:'mobile-offer'});assert.equal(f.signals[0].type,'webrtc_answer');
 await f.call.handle('192.0.2.99',{type:'call_ended'});assert.ok(f.call.session);
 await f.call.handle(peer.ip,{type:'call_ended'});assert.equal(f.call.session,null);assert.equal(f.events.filter(e=>e[0]==='end').length,0);assert.ok(f.tracks[0].stopped);
});
test('Permission denial leaves no active session or false connected state',async()=>{
 const f=setup({getUserMedia:async()=>{throw new Error('Microphone blocked');}});
 await assert.rejects(f.call.start(peer,false),/Microphone blocked/);assert.equal(f.call.session,null);assert.ok(!f.events.some(e=>e[1]==='connected'));assert.ok(!f.events.some(e=>e[0]==='invite'));
});
test('Ending while permission dialog is open stops late media and does not invite',async()=>{
 let grant;const f=setup({getUserMedia:()=>new Promise(resolve=>grant=resolve)});const pending=f.call.start(peer,false);await f.call.stop(false);grant(f.stream);await pending;assert.ok(f.tracks[0].stopped);assert.ok(!f.events.some(e=>e[0]==='invite'));
});
test('Timeout cleans media and notifies the selected peer',async()=>{
 const f=setup();await f.call.start(peer,false);const timeout=[...f.timers][0];timeout();await new Promise(setImmediate);assert.equal(f.call.session,null);assert.ok(f.events.some(e=>e[0]==='end'));assert.ok(f.tracks[0].stopped);
});
test('Listen mode never opens PC microphone and negotiates receive-only audio',async()=>{const f=setup();await f.call.start(peer,false,'listen');assert.ok(!f.events.some(e=>e[0]==='media'));assert.ok(f.pc.transceivers.some(t=>t.kind==='audio'&&t.direction==='recvonly'));await f.call.stop();});
test('Broadcast mode negotiates send-only audio',async()=>{const f=setup();await f.call.start(peer,false,'broadcast');assert.equal(f.pc.transceivers.find(t=>t.sender.track?.kind==='audio').direction,'sendonly');await f.call.handle(peer.ip,{type:'call_accepted'});assert.equal(f.pc.offerOptions.offerToReceiveAudio,false);await f.call.stop();});
test('No local audio track negotiates recvonly and still invites the phone',async()=>{
 const empty={getTracks:()=>[],getAudioTracks:()=>[],getVideoTracks:()=>[]};const f=setup({getUserMedia:async()=>empty});await f.call.start(peer,false);assert.ok(f.pc.transceivers.some(t=>t.kind==='audio'&&t.direction==='recvonly'));assert.ok(f.events.some(e=>e[0]==='invite'));await f.call.stop(false);
});
test('Broadcast cannot claim to send when no outgoing source exists',async()=>{
 const empty={getTracks:()=>[],getAudioTracks:()=>[],getVideoTracks:()=>[]};const f=setup({getUserMedia:async()=>empty});await assert.rejects(f.call.start(peer,false,'broadcast'),/No PC microphone or shared audio/);assert.ok(!f.events.some(e=>e[0]==='invite'));assert.equal(f.call.session,null);assert.ok(f.pc.closed);
});

test('Missing local camera still negotiates receiving the phone video',async()=>{
 const f=setup();await f.call.start(peer,true);assert.equal(f.pc.transceiver.kind,'video');assert.equal(f.call.session.videoTransceiver.direction,'sendrecv');await f.call.handle(peer.ip,{type:'call_accepted'});assert.equal(f.pc.offerOptions.offerToReceiveVideo,true);await f.call.stop(false);
});

function videoTrack(id){return {id,kind:'video',enabled:true,readyState:'live',stop(){this.stopped=true;this.readyState='ended';}};}
function videoStream(track){return {getTracks:()=>[track],getVideoTracks:()=>[track],getAudioTracks:()=>[]};}
async function connected(f){await f.call.start(peer,false);f.pc.connectionState='connected';f.pc.onconnectionstatechange();return f.call.session;}
test('Audio call upgrades to camera and returns to audio using the reserved sender without touching microphone',async()=>{
 const camera=videoTrack('cam');const f=setup({getUserMedia:async c=>c.video?videoStream(camera):f.stream});const s=await connected(f);
 await f.call.camera(true);assert.equal(s.videoTransceiver.sender.track,camera);assert.equal(s.video,true);assert.equal(f.pc.offers,undefined);assert.equal(f.tracks[0].enabled,true);
 await f.call.camera(false);assert.equal(s.videoTransceiver.sender.track,null);assert.equal(s.video,false);assert.equal(f.tracks[0].stopped,undefined);assert.equal(f.signals.at(-1).is_video,false);await f.call.stop(false);
});
test('Audio-only screen share does not request a webcam and stopping restores audio-only',async()=>{
 const screen=videoTrack('screen');let cameraRequests=0;const f=setup({getUserMedia:async c=>{if(c.video)cameraRequests++;return f.stream;},getDisplayMedia:async()=>videoStream(screen)});const s=await connected(f);
 await f.call.screen(true);assert.equal(cameraRequests,0);assert.equal(s.videoTransceiver.sender.track,screen);assert.equal(s.video,false);assert.equal(s.sharing,true);assert.equal(f.signals.at(-1).is_video,true);
 await f.call.screen(false);assert.equal(screen.stopped,true);assert.equal(s.videoTransceiver.sender.track,null);assert.equal(f.signals.at(-1).is_video,false);assert.equal(f.tracks[0].stopped,undefined);await f.call.stop(false);
});
test('Screen share restores an enabled camera when the OS Stop sharing action fires',async()=>{
 const camera=videoTrack('cam'),screen=videoTrack('screen');const f=setup({getUserMedia:async c=>c.video?videoStream(camera):f.stream,getDisplayMedia:async()=>videoStream(screen)});const s=await connected(f);
 await f.call.camera(true);await f.call.screen(true);screen.onended();await new Promise(setImmediate);
 assert.equal(s.sharing,false);assert.equal(s.videoTransceiver.sender.track,camera);assert.equal(s.video,true);await f.call.stop(false);
});
test('Declining display permission keeps connected audio and the existing camera state',async()=>{
 const f=setup({getDisplayMedia:async()=>{throw new Error('Cancelled');}});const s=await connected(f);await assert.rejects(f.call.screen(true),/Cancelled/);
 assert.equal(f.call.session,s);assert.equal(s.sharing,false);assert.equal(s.mediaBusy,false);assert.equal(f.tracks[0].stopped,undefined);await f.call.stop(false);
});
test('Ending during the display picker releases late capture and never switches the ended call',async()=>{
 let grant;const screen=videoTrack('late');const f=setup({getDisplayMedia:()=>new Promise(resolve=>grant=resolve)});await connected(f);const pending=f.call.screen(true);await f.call.stop(false);grant(videoStream(screen));await pending;assert.ok(screen.stopped);assert.equal(f.call.session,null);
});
test('Remote video-toggle changes remote presentation without enabling this PC camera',async()=>{
 const f=setup();const s=await connected(f);await f.call.handle(peer.ip,{type:'call_video_toggle',is_video:true});assert.equal(s.peerVideo,true);assert.equal(s.video,false);await f.call.handle(peer.ip,{type:'call_video_toggle',is_video:false});assert.equal(s.peerVideo,false);await f.call.stop(false);
});
