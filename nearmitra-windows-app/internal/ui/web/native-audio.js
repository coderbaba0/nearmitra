(function(root){
 'use strict';
 class NativeAudio {
  constructor(o){this.o=o;this.active=new Map();}
  async capture(device=''){
   const abort=new AbortController();let context,node,reader,stream,closed=false;
   const dispose=()=>{if(closed)return;closed=true;abort.abort();reader?.cancel().catch(()=>{});node?.disconnect();stream?.getTracks().forEach(t=>t.stop());if(context)Promise.resolve(context.close()).catch(()=>{});if(stream)this.active.delete(stream);};
   try{
    context=this.o.createAudioContext();await context.resume();
    if(!context.audioWorklet)throw new Error('Native system audio needs AudioWorklet support. Update Microsoft Edge.');
    // Load worklet first; never start native capture if the audio graph cannot run.
    await context.audioWorklet.addModule('/native-audio-worklet.js');
    const response=await this.o.fetch('/api/audio/loopback?device='+encodeURIComponent(device),{method:'POST',headers:{'X-NearMitra-Audio':'loopback'},signal:abort.signal});
    if(!response.ok)throw new Error(await response.text());
    const rate=Number(response.headers.get('X-Audio-Sample-Rate')),channels=Number(response.headers.get('X-Audio-Channels'));
    if(!Number.isFinite(rate)||rate<8000||rate>384000||channels!==2||!response.body)throw new Error('Invalid Windows playback audio format');
    node=this.o.createWorklet(context,'nearmitra-system-audio',{numberOfInputs:0,numberOfOutputs:1,outputChannelCount:[2],processorOptions:{inputRate:rate}});
    const destination=context.createMediaStreamDestination();node.connect(destination);stream=destination.stream;
    if(!stream.getAudioTracks().length)throw new Error('Native audio output track could not be created');
    this.active.set(stream,dispose);reader=response.body.getReader();
    const feed=async()=>{
     let remainder=new Uint8Array(0);
     try{
      while(!closed){
       const {value,done}=await reader.read();if(closed)return;if(done)throw new Error('Windows playback capture ended. Check the selected output device.');
       const data=new Uint8Array(remainder.length+value.length);data.set(remainder);data.set(value,remainder.length);const bytes=data.length-data.length%8;
       if(bytes){const samples=new Float32Array(bytes/4);const view=new DataView(data.buffer);for(let i=0;i<samples.length;i++)samples[i]=view.getFloat32(i*4,true);node.port.postMessage(samples,[samples.buffer]);}
       remainder=data.slice(bytes);
      }
     }catch(error){if(!closed){dispose();this.o.onEnded?.(error.message,stream);}}
    };
    feed();return stream;
   }catch(error){dispose();throw error;}
  }
  release(stream){this.active.get(stream)?.();}
 }
 if(typeof module!=='undefined')module.exports=NativeAudio;
 root.NearMitraNativeAudio=NativeAudio;
})(globalThis);
