const {test}=require('node:test'),assert=require('node:assert/strict'),Capture=require('./audio-capture.js');
function track(kind){return {kind,enabled:true,stop(){this.stopped=true;},listeners:{},addEventListener(name,callback){this.listeners[name]=callback;}};}
function stream(tracks){return {getTracks:()=>tracks,getAudioTracks:()=>tracks.filter(t=>t.kind==='audio'),getVideoTracks:()=>tracks.filter(t=>t.kind==='video')};}
function fixture({noSystemAudio=false,failMic=false}={}){
 const mic=track('audio'),desktop=track('audio'),screen=track('video'),camera=track('video'),mixed=track('audio');const events=[];
 const context={closed:false,inputs:[],createMediaStreamDestination:()=>({stream:stream([mixed])}),createMediaStreamSource(input){this.inputs.push(input);return {connect(){}};},async resume(){},async close(){this.closed=true;}};
 const capture=new Capture({createStream:stream,createAudioContext:()=>context,media:{async getDisplayMedia(constraints){events.push('display');return stream(noSystemAudio?[screen]:[screen,desktop]);},async getUserMedia(constraints){events.push(['mic',constraints]);if(failMic)throw new Error('mic denied');return stream(constraints.video?(constraints.audio?[mic,camera]:[camera]):[mic]);}}});
 return {capture,mic,desktop,screen,camera,mixed,context,events};
}
test('Both sources are mixed into one outgoing audio track, without transmitting screen video',async()=>{
 const f=fixture();const output=await f.capture.capture({audio:true,video:false},'both','usb-mic');assert.equal(f.events[0],'display');assert.equal(f.events[1][1].audio.deviceId.exact,'usb-mic');assert.deepEqual(output.getAudioTracks(),[f.mixed]);assert.equal(output.getVideoTracks().length,0);assert.equal(f.context.inputs.length,2);f.capture.release(output);for(const t of [f.mic,f.desktop,f.screen,f.mixed])assert.ok(t.stopped);assert.ok(f.context.closed);
});
test('System-only captures actual system sound and never opens the microphone',async()=>{const f=fixture();const output=await f.capture.capture({audio:true,video:false},'system');assert.equal(f.events.length,1);assert.deepEqual(output.getAudioTracks(),[f.desktop]);f.capture.release(output);assert.ok(f.screen.stopped);});
test('Missing Share audio fails explicitly and releases screen capture',async()=>{const f=fixture({noSystemAudio:true});await assert.rejects(f.capture.capture({audio:true},'both'),/No system audio was shared/);assert.ok(f.screen.stopped);assert.equal(f.events.length,1);});
test('Mic denial after screen capture cleans all acquired tracks',async()=>{const f=fixture({failMic:true});await assert.rejects(f.capture.capture({audio:true},'both'),/mic denied/);assert.ok(f.screen.stopped);assert.ok(f.desktop.stopped);});
test('Video calls use webcam video and mixed sound, keeping the screen video private',async()=>{const f=fixture();const output=await f.capture.capture({audio:true,video:true},'both');assert.deepEqual(output.getVideoTracks(),[f.camera]);assert.deepEqual(output.getAudioTracks(),[f.mixed]);f.capture.release(output);assert.ok(f.camera.stopped);});

test('Stopping screen sharing releases all tracks and mix context exactly once',async()=>{
 const f=fixture();let ended=0;let endedStream;
 f.capture.o.onSourceEnded=(message,output)=>{ended++;endedStream=output;};
 const output=await f.capture.capture({audio:true},'both');
 f.screen.listeners.ended();assert.equal(ended,1);assert.equal(endedStream,output);assert.ok(f.context.closed);
 for(const t of [f.screen,f.desktop,f.mic,f.mixed])assert.ok(t.stopped);
 f.desktop.listeners.ended();f.capture.release(output);assert.equal(ended,1);
});
test('Explicit call cleanup does not trigger another source-ended callback',async()=>{
 const f=fixture();let ended=0;f.capture.o.onSourceEnded=()=>ended++;
 const output=await f.capture.capture({audio:true},'system');f.capture.release(output);f.screen.listeners.ended();assert.equal(ended,0);
});
test('Sharing stopped while microphone permission was pending never returns a live call stream',async()=>{
 const f=fixture();f.screen.readyState='ended';await assert.rejects(f.capture.capture({audio:true},'both'),/stopped before capture was ready/);assert.ok(f.mic.stopped);assert.ok(f.context.closed);
});
function missingDevice(){const error=new Error('Requested device not found');error.name='NotFoundError';return error;}
test('Missing PC microphone returns receive-only media without synthesizing fake audio',async()=>{
 const f=fixture();f.capture.o.media.getUserMedia=async()=>{throw missingDevice();};f.capture.o.media.enumerateDevices=async()=>[];
 const output=await f.capture.capture({audio:true,video:false},'mic');assert.equal(output.getAudioTracks().length,0);assert.equal(f.context.inputs.length,0);assert.match(f.capture.warnings.get(output)[0],/No PC microphone/);f.capture.release(output);
});
test('Missing camera preserves working microphone for an audio-capable video call',async()=>{
 const f=fixture();f.capture.o.media.getUserMedia=async c=>{if(c.video)throw missingDevice();return stream([f.mic]);};
 const output=await f.capture.capture({audio:true,video:true},'mic');assert.equal(output.getAudioTracks()[0],f.mic);assert.equal(output.getVideoTracks().length,0);assert.match(f.capture.warnings.get(output)[0],/No PC camera/);f.capture.release(output);assert.ok(f.mic.stopped);
});
test('Removed selected microphone falls back to Windows default device',async()=>{
 const f=fixture();let calls=0;f.capture.o.media.getUserMedia=async c=>{calls++;if(c.audio.deviceId)throw missingDevice();return stream([f.mic]);};
 const output=await f.capture.capture({audio:true},'mic','removed-usb-mic');assert.equal(output.getAudioTracks()[0],f.mic);assert.equal(calls,2);f.capture.release(output);
});
test('Missing Windows default can use an enumerated physical microphone',async()=>{
 const f=fixture();f.capture.o.media.enumerateDevices=async()=>[{kind:'audioinput',deviceId:'physical-mic'}];f.capture.o.media.getUserMedia=async c=>{if(c.audio.deviceId?.exact!=='physical-mic')throw missingDevice();return stream([f.mic]);};
 const output=await f.capture.capture({audio:true},'mic');assert.equal(output.getAudioTracks()[0],f.mic);f.capture.release(output);
});
test('Permission denial never falls back as though capture hardware were missing',async()=>{
 const f=fixture();f.capture.o.media.getUserMedia=async()=>{const e=new Error('Permission denied');e.name='NotAllowedError';throw e;};await assert.rejects(f.capture.capture({audio:true},'mic'),{name:'NotAllowedError'});
});
