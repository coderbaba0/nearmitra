const {test}=require('node:test'),assert=require('node:assert/strict'),PCM=require('./native-pcm-buffer.js');
function tone(rate,seconds,hz=440){const out=new Float32Array(Math.round(rate*seconds)*2);for(let i=0;i<out.length/2;i++){out[i*2]=Math.sin(i*2*Math.PI*hz/rate);out[i*2+1]=out[i*2]*.5;}return out;}
for(const input of [44100,48000,96000])test(`Native ${input} Hz preserves 440 Hz pitch at 48 kHz playback`,()=>{
 const q=new PCM(input,48000);q.push(tone(input,.2));const left=new Float32Array(4800),right=new Float32Array(4800);q.render(left,right);
 let crossings=0;for(let i=1;i<left.length;i++)if(left[i-1]<=0&&left[i]>0)crossings++;
 assert.ok(crossings>=43&&crossings<=45,`wrong tone frequency: ${crossings*10}`);for(let i=0;i<left.length;i++)assert.ok(Math.abs(right[i]-left[i]*.5)<1e-6);
});
test('Long native bursts stay bounded instead of accumulating seconds of slow audio',()=>{const q=new PCM(48000,48000);for(let i=0;i<100;i++)q.push(tone(48000,.02));assert.ok(q.size<=q.capacity);assert.ok(q.dropped>0);});
test('Startup and underflow produce silence, never ticking/uninitialized PCM',()=>{const q=new PCM(48000,48000),l=new Float32Array(128).fill(1),r=new Float32Array(128).fill(1);q.render(l,r);assert.ok(l.every(v=>v===0));assert.ok(r.every(v=>v===0));q.push(tone(48000,.03));for(let i=0;i<30;i++)q.render(l,r);assert.ok(l.every(v=>v===0));});
