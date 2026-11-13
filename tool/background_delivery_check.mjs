// Physical-device checks using a running NearMitra Windows peer's local API.
// node tool/background_delivery_check.mjs <chat|file|replies> <scenario> [phone-ip]
// Sends labelled test data only; evidence stays in ignored build/.
import fs from 'node:fs/promises';
import crypto from 'node:crypto';

const [action, scenario = 'lock', phoneIp = '192.168.1.3'] = process.argv.slice(2);
if (!['chat', 'file', 'replies'].includes(action) || !/^[a-z0-9-]+$/.test(scenario)) {
  throw new Error('Expected chat|file|replies and a lowercase scenario name');
}
const base = 'http://127.0.0.1:43880';
const output = 'build/background-verification';
await fs.mkdir(output, {recursive: true});
const state = await fetch(`${base}/api/state`).then(r => r.json());
const peer = state.peers.find(p => p.ip === phoneIp);
if (!peer) throw new Error('Phone missing from the Windows peer discovery list');
let result;
if (action === 'replies') {
  const messages = state.chat_messages.filter(m => !m.mine && m.peer_id === peer.id &&
    m.text?.startsWith('BGV_REPLY_')).map(m => ({id: m.id, text: m.text, at: m.at}));
  result = {messages, counts: Object.fromEntries([...new Set(messages.map(m => m.text))]
    .map(text => [text, messages.filter(m => m.text === text).length]))};
} else {
  const label = `bgv-${new Date().toISOString().slice(0, 10)}-${scenario}`;
  let response;
  let expected;
  if (action === 'chat') {
    response = await fetch(`${base}/api/chat/send`, {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify({
        id: label, peer_id: peer.id, peer_ip: phoneIp, sender: 'Me',
        text: `[Background verification] ${label}`, mine: true, kind: 'text',
      }), signal: AbortSignal.timeout(30000)});
  } else {
    const name = `${label}.txt`;
    const bytes = Buffer.alloc(256 * 1024);
    const pattern = Buffer.from(`${label}: test fixture only\n`);
    for (let offset = 0; offset < bytes.length; offset += pattern.length) {
      pattern.copy(bytes, offset, 0, Math.min(pattern.length, bytes.length - offset));
    }
    expected = {name, size: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex')};
    await fs.writeFile(`${output}/${name}`, bytes);
    const form = new FormData();
    form.set('file', new Blob([bytes], {type: 'text/plain'}), name);
    response = await fetch(`${base}/api/send-file-upload?ip=${encodeURIComponent(phoneIp)}`,
      {method: 'POST', body: form, signal: AbortSignal.timeout(30000)});
  }
  const body = await response.text();
  if (!response.ok) throw new Error(`Windows send failed (${response.status}): ${body}`);
  const reply = JSON.parse(body);
  result = {label, httpStatus: response.status, expected,
    sent: {id: reply.id ?? reply.message?.id, status: reply.status ?? reply.message?.status}};
}
const record = {time: new Date().toISOString(), action, scenario, ...result};
await fs.appendFile(`${output}/results.jsonl`, `${JSON.stringify(record)}\n`);
console.log(JSON.stringify(record, null, 2));
