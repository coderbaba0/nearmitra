(function(root){
 'use strict';
 class AudioCapture {
  constructor(options){this.o=options;this.active=new Map();this.warnings=new WeakMap();}
  async capture(constraints,source='mic',deviceId=''){
   const streams=[],contexts=[],warnings=[];let output,nativeDesktop,disposed=false;
   const dispose=()=>{if(disposed)return;disposed=true;if(nativeDesktop)this.o.releaseSystemAudio?.(nativeDesktop);for(const stream of new Set([...streams,output].filter(Boolean)))stream.getTracks().forEach(t=>t.stop());for(const context of contexts)Promise.resolve(context.close()).catch(()=>{});if(output)this.active.delete(output);};
   try{
    if(!constraints.audio) return await this.o.media.getUserMedia(constraints);
    let desktop,mic;
    // Open the picker during the button's user gesture, before any microphone await.
    if(source==='system' || source==='both'){
     if(this.o.musicAudio && this.o.captureScope?.()!=='tab' && this.o.captureSystemAudio){desktop=await this.o.captureSystemAudio();nativeDesktop=desktop;}
     else desktop=await this.o.media.getDisplayMedia({video:this.o.musicAudio?{displaySurface:this.o.captureScope?.()==='tab'?'browser':'monitor'}:true,monitorTypeSurfaces:'include',audio:this.o.musicAudio?{suppressLocalAudioPlayback:false}:true,systemAudio:'include',windowAudio:'system',selfBrowserSurface:'exclude',surfaceSwitching:'include'});streams.push(desktop);
     if(!desktop.getAudioTracks().length)throw new Error('No system audio was shared. For Chrome or another PC app, choose Entire screen and enable Share system audio. Browser-tab capture only lists tabs in the browser running NearMitra.');
    }
    if(source==='mic' || source==='both' || constraints.video){
     const audio=source==='mic' || source==='both' ? {echoCancellation:true,noiseSuppression:true,autoGainControl:true,...(deviceId?{deviceId:{exact:deviceId}}:{})}:false;
     try {
      mic=await this.o.media.getUserMedia({...constraints,audio});streams.push(mic);
     }catch(error){
      if(!this.isMissingDevice(error))throw error;
      // A missing camera must not discard a working microphone, or vice versa.
      const parts=[];
      if(audio){const stream=await this.capturePart('audio',audio,constraints.video?null:error,warnings);if(stream){streams.push(stream);parts.push(...stream.getAudioTracks());}}
      if(constraints.video){const stream=await this.capturePart('video',constraints.video,null,warnings);if(stream){streams.push(stream);parts.push(...stream.getVideoTracks());}}
      mic=this.o.createStream(parts);
     }
     if(audio && !mic.getAudioTracks().length && !warnings.length)warnings.push('No PC microphone is available; your microphone audio is not being sent.');
    }
    const tracks=mic && constraints.video ? [...mic.getVideoTracks()]:[];
    const audioStreams=streams.filter(stream=>stream.getAudioTracks().length);
    if(audioStreams.length===1)tracks.push(...audioStreams[0].getAudioTracks());
    else if(audioStreams.length>1){
     const context=this.o.createAudioContext();contexts.push(context);
     const destination=context.createMediaStreamDestination();
     for(const stream of audioStreams){
      const audioOnly=this.o.createStream(stream.getAudioTracks());
      context.createMediaStreamSource(audioOnly).connect(destination);
     }
     await context.resume();tracks.push(...destination.stream.getAudioTracks());
    }
    if(desktop?.getTracks().some(track=>track.readyState==='ended'))throw new Error('System audio sharing stopped before capture was ready.');
    output=this.o.createStream(tracks);if(this.o.musicAudio)output.getAudioTracks().forEach(track=>{try{track.contentHint='music';}catch(error){warnings.push('Browser did not accept the optional music quality hint.');}});this.active.set(output,dispose);this.warnings.set(output,warnings);
    if(desktop){
     const ended=()=>{if(disposed)return;dispose();this.o.onSourceEnded?.('System audio sharing stopped. The call has ended.',output);};
     desktop.getTracks().forEach(track=>track.addEventListener('ended',ended,{once:true}));
    }
    return output;
   }catch(error){dispose();throw error;}
  }
  isMissingDevice(error){return ['NotFoundError','DevicesNotFoundError','OverconstrainedError','ConstraintNotSatisfiedError'].includes(error?.name);}
  async capturePart(kind,requested,initialError,warnings){
   const attempt=value=>this.o.media.getUserMedia({audio:kind==='audio'?value:false,video:kind==='video'?value:false});
   if(!initialError){try{return await attempt(requested);}catch(error){if(!this.isMissingDevice(error))throw error;initialError=error;}}
   if(kind==='audio'){
    const fallback={echoCancellation:true,noiseSuppression:true,autoGainControl:true};
    if(requested.deviceId){try{return await attempt(fallback);}catch(error){if(!this.isMissingDevice(error))throw error;}}
    const devices=await this.o.media.enumerateDevices?.().catch(()=>[]) || [];
    for(const device of devices.filter(d=>d.kind==='audioinput' && d.deviceId && !['default','communications',requested.deviceId?.exact].includes(d.deviceId))){
     try{return await attempt({...fallback,deviceId:{exact:device.deviceId}});}catch(error){if(!this.isMissingDevice(error))throw error;}
    }
   }
   warnings.push(kind==='audio'?'No PC microphone is available; your microphone audio is not being sent.':'No PC camera is available. Audio and incoming phone video can still work.');
   return null;
  }
  release(stream){const dispose=this.active.get(stream);if(dispose)dispose();else stream?.getTracks().forEach(t=>t.stop());}
 }
 if(typeof module!=='undefined')module.exports=AudioCapture;
 root.NearMitraAudioCapture=AudioCapture;
})(typeof globalThis!=='undefined'?globalThis:this);
