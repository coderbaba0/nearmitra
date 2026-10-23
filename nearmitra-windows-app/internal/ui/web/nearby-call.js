(function(root){
 'use strict';
 class NearbyCall {
  static resolvePeer(target,peers=[],lanDevices=[]) {
   if(typeof target==='string')target={id:target,ip:target};
   if(!target)return null;
   const byID=peers.find(peer=>peer.id===target.id);
   const ip=String(target.ip || byID?.ip || '').trim();
   const parts=ip.split('.');
   const ipv4=parts.length===4 && parts.every(part=>/^\d{1,3}$/.test(part)&&Number(part)<=255);
   if(!ipv4)return null;
   // An explicit Nearby IP is authoritative for an attempted call. UDP presence
   // and WAN identity aliases must not block or redirect its TCP invitation.
   const peer=peers.find(peer=>peer.ip===ip) || lanDevices.find(peer=>peer.ip===ip) || byID || {};
   return {...peer,id:peer.id || target.id || ip,ip,name:peer.name || peer.hostname || target.name || ip};
  }
  constructor(options){this.o=options;this.session=null;this.sequence=0;}
  state(value){if(this.o.onState)this.o.onState(value,this.session);}
  async open(peer,video,incoming,mode='duplex'){
   if(this.session)throw new Error('Another call is in progress');
   const session={peer,video,incoming,mode,token:++this.sequence,pc:null,stream:null,remoteStream:null,screenStream:null,sharing:false,peerVideo:video,mediaBusy:false,candidates:[],offered:false};
   this.session=session;this.state('permissions');
   try{
    const stream=mode==='listen' ? this.o.createStream([]) : await this.o.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:video?{width:{ideal:1280},height:{ideal:720}}:false});
    if(this.session!==session){this.release(stream);return null;}
    session.stream=stream;
    const pc=this.o.createPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]});session.pc=pc;
    stream.getAudioTracks().forEach(track=>pc.addTrack(track,stream));
    const camera=stream.getVideoTracks()[0];
    // Reserve a bidirectional video slot even for audio calls. Later camera /
    // display changes can replace its track without interrupting audio or ICE.
    session.video=!!camera && video;
    session.videoTransceiver=pc.addTransceiver(camera || 'video',{direction:'sendrecv',streams:[stream]});
    if(mode==='listen' || (mode!=='broadcast' && !stream.getAudioTracks().length))pc.addTransceiver('audio',{direction:'recvonly'});

    if(mode==='broadcast' && !stream.getAudioTracks().length)throw new Error('No PC microphone or shared audio is available to broadcast. Choose a working microphone or explicitly share system audio.');
    if(mode==='broadcast')for(const transceiver of pc.getTransceivers()){if(transceiver.sender.track?.kind==='audio')transceiver.direction='sendonly';}
    pc.onicecandidate=event=>{if(event.candidate && this.session===session)this.signal('webrtc_ice',{candidate:event.candidate.candidate,sdp_mid:event.candidate.sdpMid,sdp_mline_index:event.candidate.sdpMLineIndex}).catch(error=>this.fail(error));};
    pc.ontrack=event=>{
     if(this.session!==session)return;
     session.remoteStream ||= this.o.createStream([]);
     if(!session.remoteStream.getTracks().some(track=>track.id===event.track.id))session.remoteStream.addTrack(event.track);
     if(this.o.onRemote)this.o.onRemote(session.remoteStream,event.track);
    };
    pc.onconnectionstatechange=()=>{
     if(this.session!==session)return;
     if(pc.connectionState==='connected'){this.clearTimer(session);if(!session.connected){session.connected=true;this.state('connected');}}
     else if(pc.connectionState==='failed')this.fail(new Error('Call connection failed'));
     else if(pc.connectionState==='disconnected')this.armTimer(session,8000,'Connection lost');
    };
    if(this.o.onLocal)this.o.onLocal(stream);this.mediaState(session);
    this.armTimer(session,this.o.timeoutMs || 40000,'Call timed out');return session;
   }catch(error){if(this.session===session)await this.stop(false);throw error;}
  }
  async start(peer,video,mode='duplex'){const s=await this.open(peer,video,false,mode);if(!s)return;
   try{await this.o.invite(peer,video);if(this.session===s)this.state('ringing');}catch(error){await this.stop(false);throw error;}}
  async accept(peer,video){const s=await this.open(peer,video,true);if(!s)return;
   try{await this.o.answer(peer);if(this.session===s)this.state('connecting');}catch(error){await this.stop(false);throw error;}}
  async signal(type,extra={}){const s=this.session;if(!s)return;return this.o.sendSignal(s.peer.ip,{type,...extra});}
  async handle(ip,header){
   const s=this.session;if(!s || s.peer.ip!==ip)return;
   if(['call_ended','call_declined'].includes(header.type)){await this.stop(false);return;}
   if(header.type==='call_video_toggle'){
    s.peerVideo=header.is_video===true;this.mediaState(s);return;
   }
   if(header.type==='call_accepted'){
    if(s.incoming || s.offered)return;s.offered=true;this.state('connecting');
    const offer=await s.pc.createOffer({offerToReceiveAudio:s.mode!=='broadcast',offerToReceiveVideo:true});
    if(this.session!==s)return;await s.pc.setLocalDescription(offer);
    await this.signal('webrtc_offer',{sdp:offer.sdp,sdp_type:offer.type,is_video:s.video});
   }else if(header.type==='webrtc_offer'){
    if(!header.sdp)return;
    await s.pc.setRemoteDescription({type:header.sdp_type || 'offer',sdp:header.sdp});await this.drain(s);
    const answer=await s.pc.createAnswer();if(this.session!==s)return;
    await s.pc.setLocalDescription(answer);await this.signal('webrtc_answer',{sdp:answer.sdp,sdp_type:answer.type});
   }else if(header.type==='webrtc_answer'){
    if(!header.sdp || s.pc.signalingState==='stable')return;
    await s.pc.setRemoteDescription({type:header.sdp_type || 'answer',sdp:header.sdp});await this.drain(s);
   }else if(header.type==='webrtc_ice' && header.candidate){
    const candidate={candidate:header.candidate,sdpMid:header.sdp_mid ?? header.sdpMid ?? '0',sdpMLineIndex:header.sdp_mline_index ?? header.sdpMLineIndex ?? 0};
    if(s.pc.remoteDescription)await s.pc.addIceCandidate(candidate);else if(s.candidates.length<128)s.candidates.push(candidate);
   }
  }
  async drain(s){for(const candidate of s.candidates.splice(0)){if(this.session!==s)return;await s.pc.addIceCandidate(candidate);}}
  mediaState(s){if(this.session===s && this.o.onMedia)this.o.onMedia(s);}
  async videoChange(action){
   const s=this.session;if(!s?.connected)throw new Error('Wait for the call to connect');
   if(s.mediaBusy)throw new Error('A camera or screen change is already in progress');
   s.mediaBusy=true;this.mediaState(s);
   try{return await action(s);}finally{s.mediaBusy=false;this.mediaState(s);if(this.session===s && s.screenEnded && s.sharing){s.screenEnded=false;this.screen(false).catch(error=>this.o.onError?.(error));}}
  }
  async publishVideo(s,track){
   if(this.session!==s)return false;
   const reserved=s.videoTransceiver;
   const live=s.pc.getTransceivers().find(tx=>!tx.stopped &&
    (tx.sender===reserved.sender || (reserved.mid!=null && tx.mid===reserved.mid)));
   if(!live)throw new Error('The call video sender is unavailable; reconnect the call');
   s.videoTransceiver=live;
   const previous=live.sender.track,previousDirection=live.direction;
   const upgrade=track && live.currentDirection!=='sendrecv' && live.currentDirection!=='sendonly';
   // Check before replacing media so a pending remote/local offer leaves the
   // currently published camera or screen intact.
   if(upgrade && s.pc.signalingState!=='stable')throw new Error('Call negotiation is in progress; try again');
   let replaced=false,localOfferSet=false;
   try{
    // A mobile audio-only answer can leave this slot recvonly/inactive. The
    // next offer must explicitly permit sending before publishing video.
    if(upgrade)live.direction='sendrecv';
    await live.sender.replaceTrack(track);replaced=true;
    if(this.session!==s)return false;
    if(upgrade){
     const offer=await s.pc.createOffer();
     if(this.session!==s)return false;
     await s.pc.setLocalDescription(offer);localOfferSet=true;
     if(this.session!==s)return false;
     await this.signal('webrtc_offer',{sdp:offer.sdp,sdp_type:offer.type,is_video:true});
    }
    return this.session===s;
   }catch(error){
    if(this.session===s){
     if(localOfferSet && s.pc.signalingState==='have-local-offer')await s.pc.setLocalDescription({type:'rollback'}).catch(()=>{});
     if(replaced)await live.sender.replaceTrack(previous).catch(()=>{});
     if(upgrade)live.direction=previousDirection;
    }
    throw error;
   }
  }
  async notifyVideo(s){if(this.session===s)await this.signal('call_video_toggle',{is_video:s.sharing || s.video});}
  async camera(enabled){return this.videoChange(async s=>{
   let camera=s.stream.getVideoTracks().find(track=>track.readyState!=='ended');
   let acquired;const wasEnabled=camera?.enabled;
   try{
    if(enabled && !camera){
     acquired=await this.o.getUserMedia({audio:false,video:true});camera=acquired.getVideoTracks()[0];
     if(this.session!==s){this.release(acquired);return;}
     if(!camera)throw new Error('No camera is available');
    }
    if(camera)camera.enabled=enabled;
    if(!await this.publishVideo(s,enabled?camera:null)){if(acquired)this.release(acquired);return;}
    if(acquired)s.stream.addTrack(camera);
    const previous=s.screenStream;s.screenStream=null;s.sharing=false;s.video=enabled;
    if(previous)this.releaseScreen(previous);
    if(this.o.onLocal)this.o.onLocal(s.stream);
    await this.notifyVideo(s);
   }catch(error){if(camera && wasEnabled!==undefined)camera.enabled=wasEnabled;if(acquired && !s.stream.getVideoTracks().includes(camera))this.release(acquired);throw error;}
  });}
  releaseScreen(stream){stream.getTracks().forEach(track=>{track.onended=null;track.stop();});}
  async screen(enabled){return this.videoChange(async s=>{
   if(enabled){
    let stream;
    try{
     // The display picker is called before awaiting any media operation, so it
     // retains browser user activation and never requires a PC webcam.
     stream=await this.o.getDisplayMedia({audio:false,video:true});
     if(this.session!==s){this.releaseScreen(stream);return;}
     const track=stream.getVideoTracks()[0];if(!track)throw new Error('No shared screen was selected');
     if(!await this.publishVideo(s,track)){this.releaseScreen(stream);return;}
     s.screenStream=stream;s.sharing=true;
     track.onended=()=>{if(this.session!==s || !s.sharing)return;if(s.mediaBusy)s.screenEnded=true;else this.screen(false).catch(error=>this.o.onError?.(error));};
     if(this.o.onLocal)this.o.onLocal(stream);
    }catch(error){if(stream)this.releaseScreen(stream);throw error;}
   }else{
    const previous=s.screenStream;if(!previous)return;
    const camera=s.video?s.stream.getVideoTracks().find(track=>track.readyState!=='ended'):null;
    if(!await this.publishVideo(s,camera || null))return;
    s.screenStream=null;s.sharing=false;this.releaseScreen(previous);
    if(this.o.onLocal)this.o.onLocal(s.stream);
   }
   await this.notifyVideo(s);
  });}
  release(stream){if(this.o.releaseMedia)this.o.releaseMedia(stream);else stream.getTracks().forEach(t=>t.stop());}
  mute(muted){if(this.session?.stream)this.session.stream.getAudioTracks().forEach(t=>t.enabled=!muted);}
  clearTimer(s){if(s.timer)(this.o.clearTimeout || clearTimeout)(s.timer);s.timer=null;}
  armTimer(s,ms,message){this.clearTimer(s);s.timer=(this.o.setTimeout || setTimeout)(()=>{if(this.session===s)this.fail(new Error(message));},ms);}
  async fail(error){if(this.o.onError)this.o.onError(error);await this.stop(true);}
  async stop(notify=true){const s=this.session;if(!s)return;this.session=null;++this.sequence;this.clearTimer(s);
   if(s.pc){s.pc.ontrack=null;s.pc.onicecandidate=null;s.pc.onconnectionstatechange=null;s.pc.close();}
   if(s.screenStream)this.releaseScreen(s.screenStream);if(s.stream)this.release(s.stream);this.state('ended');
   if(notify)await this.o.end(s.peer).catch(()=>{});
  }
 }
 if(typeof module!=='undefined')module.exports=NearbyCall;
 root.NearMitraCall=NearbyCall;
})(typeof globalThis!=='undefined'?globalThis:this);
