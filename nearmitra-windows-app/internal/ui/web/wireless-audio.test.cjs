const {test}=require('node:test'),assert=require('node:assert/strict'),Wireless=require('./wireless-audio.js');
const peer={ip:'192.168.1.5',name:'Phone'},id='wa-12345678-abcd';
function track(kind='audio'){return {id:kind+'1',kind,enabled:true,stop(){this.stopped=true;}};}
function stream(tracks=[track()]){return {getTracks:()=>tracks,getAudioTracks:()=>tracks.filter(t=>t.kind==='audio'),getVideoTracks:()=>tracks.filter(t=>t.kind==='video'),addTrack:t=>tracks.push(t)};}
function setup(options={}){
 const signals=[],captures=[],states=[],plays=[],timers=new Set(),local=stream();
 const pc={added:[],candidates:[],connectionState:'new',addTransceiver(t,o){this.added.push({t,o});},async createOffer(c){this.constraints=c;return {type:'offer',sdp:'PC audio offer'};},async createAnswer(){return {type:'answer',sdp:'PC audio answer'};},async setLocalDescription(d){this.localDescription=d;},async setRemoteDescription(d){this.remoteDescription=d;},async addIceCandidate(c){this.candidates.push(c);},close(){this.closed=true;}};
 const audio=new Wireless({newID:()=>id.slice(3),createPeerConnection:()=>pc,createStream:stream,
 capture:async source=>{captures.push(source);return local;},release:s=>s.getTracks().forEach(t=>t.stop()),
 send:async(ip,h)=>signals.push({ip,...h}),play:async s=>plays.push(s),stopPlayback(){},isOccupied:()=>false,
 setTimeout:fn=>{timers.add(fn);return fn;},clearTimeout:fn=>timers.delete(fn),onChange:s=>states.push(s.status),...options});
 return {audio,pc,signals,captures,states,plays,timers,local};
}
function packet(type,extra={}){return {type:'wireless_audio_'+type,session_id:id,audio_mode:'mic',...extra};}
test('PC system audio uses separate offer and send-only audio transceiver; never a call or video track',async()=>{
 const f=setup();await f.audio.start(peer,'system');assert.deepEqual(f.captures,['system']);assert.equal(f.pc.added.length,1);assert.equal(f.pc.added[0].o.direction,'sendonly');assert.equal(f.pc.added[0].t.kind,'audio');assert.equal(f.signals[0].type,'wireless_audio_offer');assert.equal(f.signals[0].session_id,id);assert.equal(f.audio.session.live,false);
 await f.audio.handle(peer.ip,packet('answer',{sdp:'phone answer'}));assert.equal(f.audio.session.live,false);f.pc.connectionState='connected';f.pc.onconnectionstatechange();assert.equal(f.audio.session.live,true);assert.equal(f.timers.size,0);
 f.audio.mute();assert.equal(f.local.getAudioTracks()[0].enabled,false);await f.audio.stop();assert.ok(f.pc.closed);assert.ok(f.local.getTracks()[0].stopped);assert.equal(f.signals.at(-1).type,'wireless_audio_stop');
});
test('Phone microphone request receives audio without PC microphone/camera capture',async()=>{
 const f=setup();await f.audio.requestMic(peer);assert.equal(f.signals[0].type,'wireless_audio_request');assert.equal(f.captures.length,0);
 await f.audio.handle(peer.ip,packet('offer',{sdp:'phone mic'}));assert.equal(f.audio.session.pending,false);assert.equal(f.signals.at(-1).type,'wireless_audio_answer');assert.equal(f.captures.length,0);
 const t=track();f.pc.ontrack({track:t});await new Promise(setImmediate);assert.equal(f.plays.length,1);await f.audio.stop(false);
});
test('Unsolicited phone microphone offer waits for explicit approval before playback/answer',async()=>{
 const f=setup();await f.audio.handle(peer.ip,packet('offer',{sdp:'mic'}));assert.ok(f.audio.session.pending);assert.equal(f.pc.remoteDescription,undefined);assert.deepEqual(f.signals.map(s=>s.type),['wireless_audio_pending']);
 await f.audio.approve();assert.equal(f.pc.remoteDescription.sdp,'mic');assert.equal(f.signals.at(-1).type,'wireless_audio_answer');await f.audio.stop(false);
});
test('Remote system-audio request opens picker only inside owner approval action',async()=>{
 const f=setup();await f.audio.handle(peer.ip,packet('request',{audio_mode:'system'}));assert.equal(f.captures.length,0);await f.audio.approve();assert.deepEqual(f.captures,['system']);assert.equal(f.signals.at(-1).type,'wireless_audio_offer');await f.audio.stop(false);
});
test('Deny, busy call/CCTV, and incorrect session cannot hijack wireless audio',async()=>{
 const busy=setup({isOccupied:()=>true});await busy.audio.handle(peer.ip,packet('request'));assert.equal(busy.signals[0].type,'wireless_audio_reject');assert.equal(busy.audio.session,null);
 const f=setup();await f.audio.handle(peer.ip,packet('offer',{sdp:'mic'}));await f.audio.handle('192.168.1.99',packet('stop'));assert.ok(f.audio.session);await f.audio.handle(peer.ip,packet('stop',{session_id:'wa-99999999'}));assert.ok(f.audio.session);await f.audio.decline();assert.equal(f.signals.at(-1).type,'wireless_audio_reject');assert.equal(f.audio.session,null);assert.equal(f.captures.length,0);
});
test('Early ICE drains after consent and remote SDP, while duplicate offers preserve one session',async()=>{
 const f=setup();await f.audio.handle(peer.ip,packet('ice',{candidate:'early',sdp_mline_index:0}));await f.audio.handle(peer.ip,packet('offer',{sdp:'mic'}));const s=f.audio.session;await f.audio.handle(peer.ip,packet('offer',{sdp:'duplicate'}));assert.equal(f.audio.session,s);await f.audio.approve();assert.equal(f.pc.candidates[0].candidate,'early');await f.audio.stop(false);
});
test('Cancelled system picker releases session and does not send an audio offer',async()=>{
 const f=setup({capture:async()=>{throw new Error('Capture declined');}});await f.audio.start(peer);assert.equal(f.audio.session,null);assert.ok(!f.signals.some(s=>s.type==='wireless_audio_offer'));assert.match(f.audio.status,/Capture declined/);
});
test('Late display permission after Stop releases tracks and never starts a new stream',async()=>{
 let grant;const f=setup({capture:()=>new Promise(resolve=>grant=resolve)});const pending=f.audio.start(peer);await f.audio.stop(false);grant(f.local);await pending;assert.ok(f.local.getTracks()[0].stopped);assert.equal(f.signals.length,0);
});
test('Timeout and remote stop free capture without call signaling or stop echoes',async()=>{
 const f=setup();await f.audio.start(peer);await f.audio.handle(peer.ip,packet('stop'));assert.equal(f.signals.filter(s=>s.type==='wireless_audio_stop').length,0);assert.ok(f.local.getTracks()[0].stopped);
 const g=setup();await g.audio.requestMic(peer);[...g.timers][0]();await new Promise(setImmediate);assert.equal(g.audio.session,null);assert.match(g.audio.status,/did not respond/);
});
test('Blocked browser autoplay exposes an explicit resume action',async()=>{
 let blocked=true;const f=setup({play:async()=>{if(blocked)throw new Error('NotAllowedError');}});await f.audio.requestMic(peer);await f.audio.handle(peer.ip,packet('offer',{sdp:'mic'}));f.pc.ontrack({track:track()});await new Promise(setImmediate);assert.equal(f.audio.session.playbackBlocked,true);blocked=false;await f.audio.resume();assert.equal(f.audio.session.playbackBlocked,false);await f.audio.stop(false);
});

test('System source picker and explicit peer approval have separate long deadlines',async()=>{
 let resolve;const delays=[];const f=setup({capture:()=>new Promise(r=>resolve=r),setTimeout:(fn,ms)=>{delays.push(ms);return fn;},clearTimeout(){}});
 const opening=f.audio.start(peer,'system');assert.equal(delays.at(-1),120000);resolve(f.local);await opening;assert.equal(delays.at(-1),35000);
 await f.audio.handle(peer.ip,packet('pending'));assert.equal(delays.at(-1),120000);assert.equal(f.audio.session.live,false);assert.match(f.audio.status,/waiting for approval/);
 await f.audio.handle(peer.ip,packet('answer',{sdp:'approved'}));f.pc.connectionState='connected';f.pc.onconnectionstatechange();assert.ok(f.audio.session.live);
 f.pc.connectionState='disconnected';f.pc.onconnectionstatechange();assert.equal(f.audio.session.live,false);assert.match(f.audio.status,/Reconnecting/);await f.audio.stop(false);
});
test('Live audio diagnostics distinguish a silent shared tab, real sound and stalled packets',async()=>{
 const f=setup();await f.audio.start(peer,'system');const s=f.audio.session;s.live=true;
 let packets=10,level=0;
 f.pc.getStats=async()=>new Map([['source',{type:'media-source',kind:'audio',audioLevel:level}],['out',{type:'outbound-rtp',kind:'audio',packetsSent:packets}]]);
 await f.audio.sampleAudio(s);assert.match(s.audioStatus,/Captured audio is silent/);
 packets=20;level=0.2;await f.audio.sampleAudio(s);assert.match(s.audioStatus,/PC capture has sound/);
 await f.audio.sampleAudio(s);assert.match(s.audioStatus,/not flowing/);
 await f.audio.stop(false);
});
