// Node 22+, no packages. Connect to a forwarded Dart VM service in profile mode.
// node tool/profile_capture.mjs <http-or-ws-VM-URI> <seconds> <output.json>
import fs from 'node:fs/promises';
import path from 'node:path';

const [address, duration = '30', output = 'build/performance-review/capture.json', gcOption] = process.argv.slice(2);
if (!address || !Number.isFinite(Number(duration)) || Number(duration) <= 0) {
  throw new Error('Expected VM service URI, positive duration in seconds, and output path');
}
const endpoint = address.startsWith('@')
  ? (await fs.readFile(address.slice(1), 'utf8')).trim() : address;
const uri = new URL(endpoint);
uri.protocol = uri.protocol === 'https:' || uri.protocol === 'wss:' ? 'wss:' : 'ws:';
if (!uri.pathname.endsWith('/ws')) uri.pathname = `${uri.pathname.replace(/\/$/, '')}/ws`;
const socket = new WebSocket(uri);
const pending = new Map();
let sequence = 0;
let recording = false;
const frames = [];
socket.addEventListener('message', ({data}) => {
  const message = JSON.parse(data);
  if (message.id != null) {
    const request = pending.get(String(message.id));
    if (!request) return;
    pending.delete(String(message.id));
    clearTimeout(request.timeout);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  } else if (recording && message.method === 'streamNotify') {
    const event = message.params?.event;
    if (event?.extensionKind === 'Flutter.Frame') frames.push(event.extensionData);
  }
});
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = String(++sequence);
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`VM service timeout: ${method}`));
    }, 20000);
    pending.set(id, {resolve, reject, timeout});
    socket.send(JSON.stringify({jsonrpc: '2.0', id, method, params}));
  });
}
await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('VM connection timed out')), 15000);
  socket.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, {once: true});
  socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('VM connection failed')); }, {once: true});
});
let timer;
let previousFlags;
let previousProfiler;
try {
  const vm = await rpc('getVM');
  const flags = (await rpc('getFlagList')).flags.filter((flag) =>
    /precompiled|profile|product|enable_asserts/.test(flag.name));
  previousProfiler = flags.find((flag) => flag.name === 'profiler')?.valueAsString;
  if (flags.find((flag) => flag.name === 'precompiled_mode')?.valueAsString !== 'true' ||
      flags.find((flag) => flag.name === 'enable_asserts')?.valueAsString !== 'false') {
    throw new Error('An AOT profile build with assertions disabled is required; debug timings are not comparable');
  }
  console.log(JSON.stringify({vm: vm.version, flags: Object.fromEntries(
    flags.filter((flag) => ['precompiled_mode', 'enable_asserts', 'profiler'].includes(flag.name))
      .map((flag) => [flag.name, flag.valueAsString]))}));
  const isolate = vm.isolates.find((entry) => entry.name === 'main') ?? vm.isolates[0];
  if (!isolate) throw new Error('No application isolate');
  const isolateId = isolate.id;
  const notes = [];
  await rpc('streamListen', {streamId: 'Extension'});
  previousFlags = (await rpc('getVMTimelineFlags')).recordedStreams;
  await rpc('setVMTimelineFlags', {recordedStreams: ['Dart', 'Embedder', 'GC']});
  try { await rpc('setFlag', {name: 'profiler', value: 'true'}); }
  catch (error) { notes.push(`Profiler flag: ${error.message}`); }
  const memory = [];
  let retainedHeapBefore;
  if (gcOption === '--gc') {
    await rpc('getAllocationProfile', {isolateId, gc: true});
    retainedHeapBefore = await rpc('getMemoryUsage', {isolateId});
  }
  const readMemory = async () => {
    memory.push({time: new Date().toISOString(), ...await rpc('getMemoryUsage', {isolateId})});
  };
  await readMemory();
  const started = (await rpc('getVMTimelineMicros')).timestamp;
  const wallStart = Date.now();
  recording = true;
  console.log(`Recording ${duration}s: ${isolate.name}, process ${vm.pid}`);
  timer = setInterval(() => readMemory().catch((error) => notes.push(error.message)), 5000);
  await new Promise((resolve) => setTimeout(resolve, Number(duration) * 1000));
  recording = false;
  const wallEnd = Date.now();
  clearInterval(timer);
  await readMemory();
  const ended = (await rpc('getVMTimelineMicros')).timestamp;
  let cpu;
  try {
    cpu = await rpc('getCpuSamples', {isolateId, timeOriginMicros: started, timeExtentMicros: ended - started});
  } catch (error) { notes.push(`CPU samples unavailable: ${error.message}`); }
  const timeline = await rpc('getVMTimeline', {timeOriginMicros: started, timeExtentMicros: ended - started});
  let retainedHeapAfter;
  let retainedRenderers;
  if (gcOption === '--gc') {
    const allocation = await rpc('getAllocationProfile', {isolateId, gc: true});
    retainedHeapAfter = await rpc('getMemoryUsage', {isolateId});
    retainedRenderers = allocation.members?.filter((entry) =>
      /RTCVideoRenderer|MediaStreamNative/.test(entry.class?.name ?? ''));
  }
  const percentile = (values, fraction) => {
    if (!values.length) return null;
    const sorted = [...values].sort((a, b) => a - b);
    return +(sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)] / 1000).toFixed(3);
  };
  const timing = (field) => ({p50Ms: percentile(frames.map((frame) => frame[field]), 0.5),
    p95Ms: percentile(frames.map((frame) => frame[field]), 0.95),
    p99Ms: percentile(frames.map((frame) => frame[field]), 0.99),
    maxMs: percentile(frames.map((frame) => frame[field]), 1)});
  const topFunctions = [...(cpu?.functions ?? [])].sort((a, b) => b.exclusiveTicks - a.exclusiveTicks)
    .slice(0, 15).map((entry) => ({name: entry.function?.name ?? entry.function,
      exclusiveTicks: entry.exclusiveTicks, inclusiveTicks: entry.inclusiveTicks, url: entry.resolvedUrl}));
  const summary = {durationSeconds: (wallEnd - wallStart) / 1000, processId: vm.pid, vmVersion: vm.version, flags,
    frameBudgetMs: 1000 / 60, frameCount: frames.length,
    // Build and raster run in a pipeline; their sum is not a missed-frame test.
    slowFrames: frames.filter((frame) => Math.max(frame.build, frame.raster) > 1000000 / 60).length,
    build: timing('build'), raster: timing('raster'), vsyncOverhead: timing('vsyncOverhead'),
    memory, retainedHeapBefore, retainedHeapAfter, retainedRenderers,
    cpuSamples: cpu?.sampleCount ?? 0, topFunctions, notes};
  await fs.mkdir(path.dirname(output), {recursive: true});
  await fs.writeFile(output, JSON.stringify({summary, frames, cpu, timeline}, null, 2));
  console.log(JSON.stringify({...summary, flags: undefined,
    memory: {first: memory[0], last: memory.at(-1)}, topFunctions: topFunctions.slice(0, 5)}, null, 2));
} finally {
  clearInterval(timer);
  if (previousFlags) await rpc('setVMTimelineFlags', {recordedStreams: previousFlags}).catch(() => {});
  if (previousProfiler != null) await rpc('setFlag', {name: 'profiler', value: previousProfiler}).catch(() => {});
  socket.close();
}
