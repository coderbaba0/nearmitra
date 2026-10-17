import './native-pcm-buffer.js';
class NearMitraSystemAudioProcessor extends AudioWorkletProcessor {
 constructor(options){super();this.queue=new globalThis.NearMitraPCMBuffer(options.processorOptions.inputRate,sampleRate);this.port.onmessage=e=>this.queue.push(e.data);}
 process(inputs,outputs){const out=outputs[0];if(out?.length>=2)this.queue.render(out[0],out[1]);return true;}
}
registerProcessor('nearmitra-system-audio',NearMitraSystemAudioProcessor);
