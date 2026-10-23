const {test}=require('node:test'),assert=require('node:assert/strict'),Native=require('./native-audio.js');
function fixture(){
 const sent=[],ended=[],requests=[];let stop=false,closed=false,resolve;
 const track={kind:'audio',stop(){stop=true;}},stream={getTracks:()=>[track],getAudioTracks:()=>[track]};
 const node={port:{postMessage:s=>sent.push([...s])},connect(){},disconnect(){}};
 const context={audioWorklet:{async addModule(url){assert.equal(url,'/native-audio-worklet.js');}},async resume(){},async close(){closed=true;},createMediaStreamDestination:()=>({stream})};
 const reader={read:()=>new Promise(r=>resolve=r),async cancel(){resolve?.({done:true});}};
 const response={ok:true,headers:new Headers({'X-Audio-Sample-Rate':'44100','X-Audio-Channels':'2'}),body:{getReader:()=>reader}};
 const engine=new Native({createAudioContext:()=>context,createWorklet:(ctx,name,options)=>{assert.equal(options.processorOptions.inputRate,44100);return node;},fetch:async(url,options)=>{requests.push({url,options});return response;},onEnded:(message)=>ended.push(message)});
 return {engine,sent,ended,requests,response,stream,get closed(){return closed;},get stopped(){return stop;},emit:value=>resolve({value,done:false}),end:()=>resolve({done:true})};
}
test('Native capture preserves interleaved PCM across fragmented HTTP boundaries and releases capture on stop',async()=>{
 const f=fixture(),stream=await f.engine.capture('output/id');assert.equal(stream,f.stream);assert.equal(f.requests[0].options.method,'POST');assert.equal(f.requests[0].options.headers['X-NearMitra-Audio'],'loopback');assert.match(f.requests[0].url,/output%2Fid/);
 const bytes=new Uint8Array(new Float32Array([.25,-.5,.75,-1]).buffer);
 f.emit(bytes.slice(0,3));await new Promise(setImmediate);assert.equal(f.sent.length,0);
 f.emit(bytes.slice(3,11));await new Promise(setImmediate);assert.deepEqual(f.sent[0],[.25,-.5]);
 f.emit(bytes.slice(11));await new Promise(setImmediate);assert.deepEqual(f.sent[1],[.75,-1]);
 f.engine.release(stream);await new Promise(setImmediate);assert.ok(f.closed);assert.ok(f.stopped);assert.equal(f.ended.length,0);assert.ok(f.requests[0].options.signal.aborted);
});
test('Native capture errors close the audio graph and show the real device failure',async()=>{
 const f=fixture();f.response.ok=false;f.response.text=async()=> 'No active Windows playback device';await assert.rejects(f.engine.capture(),/No active Windows playback device/);assert.ok(f.closed);
});
test('Native capture source removal stops tracks and reports failure rather than endless silence',async()=>{
 const f=fixture();await f.engine.capture();f.end();await new Promise(setImmediate);assert.ok(f.stopped);assert.match(f.ended[0],/playback capture ended/);
});
