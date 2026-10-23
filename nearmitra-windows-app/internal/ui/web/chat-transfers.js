(function(root){
 'use strict';
 function message(t){
  const total=Math.max(0,Number(t.BytesTotal)||0),bytes=Math.max(0,Number(t.BytesSent)||0);
  return {id:t.ID,peer_id:t.PeerID,peer_ip:t.PeerIP,sender:t.PeerName,mine:false,at:t.StartTime,kind:t.Kind || 'file',_liveTransfer:true,
   status:t.Error?'Failed':t.Complete?'Delivered':'Receiving',
   attachment:{name:t.FileName,size:total,type:t.Kind || 'file',progress:t.Complete?100:total?Math.min(99,Math.floor(bytes/total*100)):0,
    status:t.Error?'Failed':t.Complete?'Received':'Downloading',bytes,total,speed:Number(t.SpeedMBps)||0,eta:Number.isFinite(t.ETASeconds)?t.ETASeconds:-1,error:t.Error || ''}};
 }
 function project(messages,transfers){
  const stored=new Map((messages || []).map(m=>[m.id,m]));
  for(const t of transfers || []){
   if(t.Direction!=='download'||!t.ID||(!t.PeerID&&!t.PeerIP)||stored.has(t.ID))continue;
   stored.set(t.ID,message(t));
  }
  return [...stored.values()];
 }
 function detail(a,format){
  if(a.error)return 'Transfer failed: '+a.error;
  const bytes=format(a.bytes || 0)+' / '+format(a.total || 0);
  const speed=a.speed>0?a.speed.toFixed(1)+' MB/s':'Calculating speed…';
  const eta=a.eta>=0?(a.eta<1?'Less than 1s':a.eta<60?Math.ceil(a.eta)+'s':Math.ceil(a.eta/60)+' min'):'Calculating…';
  return bytes+' • '+speed+' • ETA '+eta;
 }
 const api={project,message,detail};if(typeof module!=='undefined')module.exports=api;root.NearMitraTransfers=api;
})(globalThis);
