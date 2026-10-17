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
   const session={peer,video,incoming,mode,token:++this.sequence,pc:null,stream:null,candidates:[],offered:false};
   this.session=session;this.state('permissions');
   try{
    const stream=mode==='listen' ? this.o.createStream([]) : await this.o.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:video?{width:{ideal:1280},height:{ideal:720}}:false});
    if(this.session!==session){this.release(stream);return null;}
    session.stream=stream;
    const pc=this.o.createPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]});session.pc=pc;
    stream.getTracks().forEach(track=>pc.addTrack(track,stream));
    if(mode==='listen' || (mode!=='broadcast' && !stream.getAudioTracks().length))pc.addTransceiver('audio',{direction:'recvonly'});
    if(video && !stream.getVideoTracks().length)pc.addTransceiver('video',{direction:'recvonly'});
    if(mode==='broadcast' && !stream.getAudioTracks().length)throw new Error('No PC microphone or shared audio is available to broadcast. Choose a working microphone or explicitly share system audio.');
    if(mode==='broadcast')for(const transceiver of pc.getTransceivers()){if(transceiver.sender.track?.kind==='audio')transceiver.direction='sendonly';}
    pc.onicecandidate=event=>{if(event.candidate && this.session===session)this.signal('webrtc_ice',{candidate:event.candidate.candidate,sdp_mid:event.candidate.sdpMid,sdp_mline_index:event.candidate.sdpMLineIndex}).catch(error=>this.fail(error));};
    pc.ontrack=event=>{if(this.session===session && this.o.onRemote)this.o.onRemote(event.streams[0] || new MediaStream([event.track]),event.track);};
    pc.onconnectionstatechange=()=>{
     if(this.session!==session)return;
     if(pc.connectionState==='connected'){this.clearTimer(session);if(!session.connected){session.connected=true;this.state('connected');}}
     else if(pc.connectionState==='failed')this.fail(new Error('Call connection failed'));
     else if(pc.connectionState==='disconnected')this.armTimer(session,8000,'Connection lost');
    };
    if(this.o.onLocal)this.o.onLocal(stream);
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
   if(header.type==='call_accepted'){
    if(s.incoming || s.offered)return;s.offered=true;this.state('connecting');
    const offer=await s.pc.createOffer({offerToReceiveAudio:s.mode!=='broadcast',offerToReceiveVideo:s.video});
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
  async camera(enabled){const s=this.session;if(!s)return;
   let track=s.stream.getVideoTracks()[0];
   if(enabled && !track){const stream=await this.o.getUserMedia({video:true});track=stream.getVideoTracks()[0];
    if(this.session!==s){stream.getTracks().forEach(t=>t.stop());return;}
    s.stream.addTrack(track);s.pc.addTrack(track,s.stream);
    const offer=await s.pc.createOffer();await s.pc.setLocalDescription(offer);await this.signal('webrtc_offer',{sdp:offer.sdp,sdp_type:offer.type,is_video:true});
   }
   if(track)track.enabled=enabled;s.video=enabled;await this.signal('call_video_toggle',{is_video:enabled});
  }
  release(stream){if(this.o.releaseMedia)this.o.releaseMedia(stream);else stream.getTracks().forEach(t=>t.stop());}
  mute(muted){if(this.session?.stream)this.session.stream.getAudioTracks().forEach(t=>t.enabled=!muted);}
  clearTimer(s){if(s.timer)(this.o.clearTimeout || clearTimeout)(s.timer);s.timer=null;}
  armTimer(s,ms,message){this.clearTimer(s);s.timer=(this.o.setTimeout || setTimeout)(()=>{if(this.session===s)this.fail(new Error(message));},ms);}
  async fail(error){if(this.o.onError)this.o.onError(error);await this.stop(true);}
  async stop(notify=true){const s=this.session;if(!s)return;this.session=null;++this.sequence;this.clearTimer(s);
   if(s.pc){s.pc.ontrack=null;s.pc.onicecandidate=null;s.pc.onconnectionstatechange=null;s.pc.close();}
   if(s.stream)this.release(s.stream);this.state('ended');
   if(notify)await this.o.end(s.peer).catch(()=>{});
  }
 }
 if(typeof module!=='undefined')module.exports=NearbyCall;
 root.NearMitraCall=NearbyCall;
})(typeof globalThis!=='undefined'?globalThis:this);
