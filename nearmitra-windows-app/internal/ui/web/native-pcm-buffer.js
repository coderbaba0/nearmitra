(function(root){
 'use strict';
 // Native-rate interleaved stereo to AudioContext-rate output. Never guess 48 kHz.
 class PCMBuffer {
  constructor(inputRate,outputRate){
   if(!Number.isFinite(inputRate)||inputRate<8000||inputRate>384000||!Number.isFinite(outputRate)||outputRate<8000)throw new Error('Invalid native audio sample rate');
   this.ratio=inputRate/outputRate;this.capacity=Math.ceil(inputRate*.25);this.target=Math.ceil(inputRate*.06);this.startup=Math.ceil(inputRate*.025);this.data=new Float32Array(this.capacity*2);this.read=0;this.size=0;this.phase=0;this.started=false;this.dropped=0;
  }
  push(samples){
   if(samples.length%2)throw new Error('Stereo PCM packet is not frame aligned');
   let frames=samples.length/2,offset=0;
   if(frames>this.capacity){offset=frames-this.capacity;frames=this.capacity;this.dropped+=offset;}
   if(this.size+frames>this.capacity){const drop=Math.min(this.size,Math.max(this.size+frames-this.target,0));this.read=(this.read+drop)%this.capacity;this.size-=drop;this.phase=0;this.dropped+=drop;}
   for(let i=0;i<frames;i++){const at=(this.read+this.size+i)%this.capacity;this.data[at*2]=samples[(offset+i)*2];this.data[at*2+1]=samples[(offset+i)*2+1];}this.size+=frames;
  }
  render(left,right){
   left.fill(0);right.fill(0);
   if(!this.started){if(this.size<this.startup)return;this.started=true;}
   for(let i=0;i<left.length;i++){
    const index=Math.floor(this.phase),fraction=this.phase-index;
    if(index+1>=this.size){const consumed=Math.min(index,this.size);this.read=(this.read+consumed)%this.capacity;this.size-=consumed;this.phase=0;this.started=false;break;}
    const a=(this.read+index)%this.capacity,b=(a+1)%this.capacity;
    left[i]=this.data[a*2]*(1-fraction)+this.data[b*2]*fraction;right[i]=this.data[a*2+1]*(1-fraction)+this.data[b*2+1]*fraction;this.phase+=this.ratio;
   }
   const used=Math.min(Math.floor(this.phase),this.size);this.read=(this.read+used)%this.capacity;this.size-=used;this.phase-=used;
  }
 }
 if(typeof module!=='undefined')module.exports=PCMBuffer;
 root.NearMitraPCMBuffer=PCMBuffer;
})(globalThis);
