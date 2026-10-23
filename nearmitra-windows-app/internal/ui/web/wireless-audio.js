(function(root){
 'use strict';
 class WirelessAudio {
  constructor(o){this.o=o;this.session=null;this.status='Ready for wireless audio';this.early=new Map();}
  changed(text){if(text)this.status=text;this.o.onChange?.(this);}
  current(s){return this.session===s;}
  arm(s,reason,delay){this.clear(s);s.timer=(this.o.setTimeout || setTimeout)(()=>{if(this.current(s))this.stop(true,reason);},delay || this.o.timeoutMs || 35000);}
  clear(s){if(s.timer)(this.o.clearTimeout || clearTimeout)(s.timer);s.timer=null;}
  create(peer,source,id){
   if(this.session || this.o.isOccupied?.())throw new Error('Stop the current call or stream first');
   if(!peer?.ip || !/^\d{1,3}(\.\d{1,3}){3}$/.test(peer.ip) || peer.ip.split('.').some(p=>Number(p)>255))throw new Error('Select a direct Nearby / P2P device');
   const s={id:id || 'wa-'+this.o.newID(),peer,source,sending:false,pending:false,awaitingOffer:false,live:false,pc:null,local:null,remote:null,candidates:[],hasRemote:false};
   this.session=s;this.arm(s,'Peer did not respond. Update NearMitra on both devices and retry.');return s;
  }
  signal(s,kind,extra={}){return this.o.send(s.peer.ip,{type:'wireless_audio_'+kind,session_id:s.id,stream_type:'wireless_audio',audio_mode:s.source,...extra});}
  async requestMic(peer){const s=this.create(peer,'mic');s.awaitingOffer=true;this.changed('Waiting for '+peer.name+' to allow microphone access');
   try{await this.signal(s,'request');}catch(e){if(this.current(s))await this.stop(false,e.message);}}
  async start(peer,source='system'){const s=this.create(peer,source);await this.sendAudio(s);}
  async sendAudio(s){
   s.sending=true;s.pending=false;this.arm(s,'Audio sharing was not completed. Select a source and enable Share audio, then retry.',this.o.permissionTimeoutMs || 120000);this.changed('Choose the audio source to share…');
   let stage='opening shared audio';
   try{
    const stream=await this.o.capture(s.source);
    if(!this.current(s)){this.o.release(stream);return;}
    s.local=stream;if(!stream.getAudioTracks().length)throw new Error(s.source==='mic'?'No PC microphone is available. Choose System audio above for YouTube or music.':'No outgoing audio track is available. Enable Share audio in the source picker.');
    stage='preparing audio connection';const pc=this.connection(s);stream.getAudioTracks().forEach(t=>pc.addTransceiver(t,{direction:'sendonly',streams:[stream]}));
    const offer=await pc.createOffer({offerToReceiveAudio:false,offerToReceiveVideo:false});
    if(!this.current(s))return;await pc.setLocalDescription(offer);
    if(!this.current(s))return;this.arm(s,'No audio response from the device. Keep the updated NearMitra app open on both devices and retry.');this.changed('Waiting for '+s.peer.name+' to allow audio playback');
    stage='sending audio offer';await this.signal(s,'offer',{sdp:offer.sdp,sdp_type:offer.type});
   }catch(e){if(this.current(s))await this.stop(true,'Wireless audio failed while '+stage+': '+(e?.message || String(e)));}
  }
  connection(s){
   const pc=this.o.createPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}],iceTransportPolicy:'all'});s.pc=pc;
   pc.onicecandidate=e=>{if(this.current(s)&&e.candidate)this.signal(s,'ice',{candidate:e.candidate.candidate,sdp_mid:e.candidate.sdpMid,sdp_mline_index:e.candidate.sdpMLineIndex}).catch(error=>{if(this.current(s))this.stop(true,error.message);});};
   pc.ontrack=e=>{
    if(!this.current(s)||s.sending||e.track.kind!=='audio')return;
    s.remote ||= this.o.createStream([]);
    if(!s.remote.getTracks().some(t=>t.id===e.track.id))s.remote.addTrack(e.track);
    this.o.play(s.remote).catch(error=>{if(this.current(s)){s.playbackBlocked=true;this.changed('Audio is ready. Click Play audio to enable playback.');}});
   };
   pc.onconnectionstatechange=()=>{
    if(!this.current(s))return;
    if(pc.connectionState==='connected'){s.live=true;this.clear(s);this.monitor(s);this.changed((s.sending?'Sending PC audio to ':'Receiving wireless microphone from ')+s.peer.name);}
    else if(pc.connectionState==='failed')this.stop(true,'Wireless audio connection failed');
    else if(pc.connectionState==='disconnected'){s.live=false;this.changed('Reconnecting to '+s.peer.name+'…');this.arm(s,'Wireless audio connection lost. Reconnect both devices to the same Wi-Fi and retry.');}
   };return pc;
  }
  monitor(s){
   if(s.statsTimer || !s.pc?.getStats)return;
   s.audioStatus='Checking actual audio levels…';
   this.sampleAudio(s);
   s.statsTimer=(this.o.setInterval || setInterval)(()=>this.sampleAudio(s),2000);
  }
  async sampleAudio(s){
   if(!this.current(s)||!s.live||s.readingStats)return;
   s.readingStats=true;
   try{
    const reports=await s.pc.getStats();if(!this.current(s))return;
    let level=null,packets=null;
    reports.forEach(stat=>{
     if((stat.kind || stat.mediaType)!=='audio' || stat.isRemote)return;
     if(stat.type===(s.sending?'outbound-rtp':'inbound-rtp'))packets=Number(stat[s.sending?'packetsSent':'packetsReceived']);
     if(stat.type===(s.sending?'media-source':'inbound-rtp')){
      if(Number.isFinite(stat.audioLevel))level=stat.audioLevel;
      if(Number.isFinite(stat.totalAudioEnergy)&&Number.isFinite(stat.totalSamplesDuration)){
       const previous=s.audioEnergy;s.audioEnergy={energy:stat.totalAudioEnergy,duration:stat.totalSamplesDuration};
       const duration=previous?stat.totalSamplesDuration-previous.duration:0;
       if(duration>0)level=Math.sqrt(Math.max(0,(stat.totalAudioEnergy-previous.energy)/duration));
      }
     }
    });
    const flowing=packets!==null && Number.isFinite(packets) && (s.audioPackets==null?packets>0:packets>s.audioPackets);
    s.audioPackets=packets;
    if(s.muted)s.audioStatus='Outgoing audio is muted';
    else if(packets!==null&&!flowing)s.audioStatus='Connected, but audio packets are not flowing. Check the network and restart audio.';
    else if(level!==null&&level<0.001)s.audioStatus=s.sending?'Captured audio is silent. Play the selected YouTube tab, unmute it, and check Share tab audio.':'Received audio is silent. Check playback in the selected PC tab.';
    else if(level!==null)s.audioStatus=(s.sending?'PC capture has sound':'Incoming audio has sound')+' • level '+Math.round(Math.min(1,level)*100)+'%';
    else s.audioStatus=flowing?'Audio packets are flowing; source level is unavailable.':'Audio level statistics are unavailable.';
    this.changed();
   }catch(e){if(this.current(s)){s.audioStatus='Audio diagnostics unavailable';this.changed();}}
   finally{s.readingStats=false;}
  }
  async drain(s){for(const c of s.candidates.splice(0)){if(!this.current(s))return;await s.pc.addIceCandidate(c);}}
  async approve(){const s=this.session;if(!s?.pending)return;s.pending=false;this.arm(s,'Wireless audio could not connect. Check the Wi-Fi connection and Windows private-network firewall permission.');this.changed('Connecting wireless audio…');
   if(!s.offer)return this.sendAudio(s);return this.receive(s,s.offer);}
  async decline(){const s=this.session;if(!s?.pending)return;await this.signal(s,'reject',{reason:'Device owner declined wireless audio'}).catch(()=>{});if(this.current(s))await this.stop(false,'Wireless audio declined');}
  async receive(s,h){
   try{
    s.awaitingOffer=false;s.sending=false;this.arm(s,'Audio could not connect. Check Wi-Fi and the Windows private-network firewall permission.');const pc=this.connection(s);
    await pc.setRemoteDescription({type:'offer',sdp:h.sdp});s.hasRemote=true;await this.drain(s);
    if(!this.current(s))return;const answer=await pc.createAnswer();await pc.setLocalDescription(answer);
    if(!this.current(s))return;await this.signal(s,'answer',{sdp:answer.sdp,sdp_type:answer.type});if(this.current(s)&&!s.live)this.changed('Connecting to '+s.peer.name+'…');
   }catch(e){if(this.current(s))await this.stop(true,e.message);}
  }
  async handle(ip,h){
   const id=h.session_id;if(!/^wa-[A-Za-z0-9-]{8,80}$/.test(id || ''))return;
   let s=this.session;const matches=s && s.id===id && s.peer.ip===ip;
   if(['wireless_audio_request','wireless_audio_offer'].includes(h.type)){
    if(matches){if(h.type==='wireless_audio_offer' && s.awaitingOffer && h.sdp)await this.receive(s,h);return;}
    if(s || this.o.isOccupied?.()){await this.o.send(ip,{type:'wireless_audio_reject',session_id:id,reason:'Device is busy'});return;}
    if(h.type==='wireless_audio_offer' && !h.sdp)return;
    const source=h.audio_mode || 'mic';
    if(!['system','mic','both'].includes(source)){await this.o.send(ip,{type:'wireless_audio_reject',session_id:id,reason:'Unsupported audio source'});return;}
    s=this.create({ip,name:h.sender || ip},source,id);s.pending=true;s.offer=h.type==='wireless_audio_offer'?{...h}:null;
    s.candidates=this.early.get(ip+'/'+id) || [];this.early.delete(ip+'/'+id);
    this.arm(s,'Audio permission request expired. Retry from the other device.',this.o.permissionTimeoutMs || 120000);
    await this.signal(s,'pending').catch(()=>{});if(!this.current(s))return;
    this.changed(s.offer?s.peer.name+' wants to play microphone audio on this PC':s.peer.name+' requests PC audio. Allow and choose Share audio.');return;
   }
   if(h.type==='wireless_audio_ice' && !matches){
    if(this.early.size>=8)this.early.delete(this.early.keys().next().value);
    const key=ip+'/'+id,list=this.early.get(key)||[];if(list.length<64 && h.candidate)list.push(this.candidate(h));this.early.set(key,list);return;
   }
   if(!matches)return;
   try{
    if(h.type==='wireless_audio_pending'){this.arm(s,'The other device did not approve audio. Keep NearMitra open and allow the request.',this.o.permissionTimeoutMs || 120000);this.changed('Device reached: '+s.peer.name+' • waiting for approval');}
    else if(h.type==='wireless_audio_answer' && s.sending && s.pc && !s.hasRemote && !s.answering && h.sdp){
     s.answering=true;await s.pc.setRemoteDescription({type:'answer',sdp:h.sdp});s.hasRemote=true;await this.drain(s);
    }else if(h.type==='wireless_audio_ice' && h.candidate){
     if(s.hasRemote && s.pc)await s.pc.addIceCandidate(this.candidate(h));else if(s.candidates.length<64)s.candidates.push(this.candidate(h));
    }else if(['wireless_audio_stop','wireless_audio_reject'].includes(h.type)){await this.stop(false,h.reason || 'Wireless audio stopped by peer');}
   }catch(e){if(this.current(s))await this.stop(true,e.message);}
  }
  candidate(h){return {candidate:h.candidate,sdpMid:h.sdp_mid ?? '0',sdpMLineIndex:h.sdp_mline_index ?? 0};}
  mute(){const s=this.session;if(!s?.sending)return;s.muted=!s.muted;s.local?.getAudioTracks().forEach(t=>t.enabled=!s.muted);this.changed();}
  async resume(){const s=this.session;if(!s?.remote)return;await this.o.play(s.remote);s.playbackBlocked=false;this.changed();}
  async stop(notify=true,reason='Wireless audio stopped'){
   const s=this.session;if(!s)return;this.session=null;this.clear(s);if(s.statsTimer)(this.o.clearInterval || clearInterval)(s.statsTimer);this.early.delete(s.peer.ip+'/'+s.id);
   if(notify)this.signal(s,'stop',{reason}).catch(()=>{});
   if(s.pc){s.pc.ontrack=null;s.pc.onicecandidate=null;s.pc.onconnectionstatechange=null;s.pc.close();}
   if(s.local)this.o.release(s.local);if(s.remote)this.o.release(s.remote);this.o.stopPlayback?.();this.changed(reason);
  }
 }
 if(typeof module!=='undefined')module.exports=WirelessAudio;
 root.NearMitraWirelessAudio=WirelessAudio;
})(typeof globalThis!=='undefined'?globalThis:this);
