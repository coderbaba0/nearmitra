(function(root) {
  'use strict';
  const clean = value => String(value || '').replace(/^wan:\/\//, '');
  function canonical(id, links) { id = clean(id); return (links || {})[id] || id; }
  function learn(peers, links) {
    for (const peer of peers || []) {
      if (peer.internet_device_id && peer.internet_device_id !== 'unknown_device_id') links[peer.id] = peer.internet_device_id;
    }
    return links;
  }
  function resolve(peer, peers, wan, links, connectedID) {
    if (!peer) return {mode:'offline'};
    const id = canonical(peer.internet_device_id || peer.id, links);
    const nearby = (peers || []).find(p => canonical(p.internet_device_id || p.id, links) === id && p.is_online !== false && p.ip && !p.ip.startsWith('wan'));
    const internet = ((wan && wan.trusted_devices) || []).find(p => p.id === id);
    return {id, nearby, internet, mode:nearby ? 'nearby' : wan && wan.internet_mode_enabled && internet && (internet.is_online || connectedID === id) ? 'wan' : 'offline'};
  }
  function matches(message, peer, peers, links) {
    if (!peer) return false;
    const id = canonical(peer.internet_device_id || peer.id, links);
    if (canonical(message.peer_id, links) === id || canonical(message.peer_ip, links) === id) return true;
    const local = (peers || []).find(p => canonical(p.internet_device_id || p.id, links) === id);
    const ip = local ? local.ip : !peer.is_wan && peer.ip;
    return !!ip && (message.peer_ip === ip || message.peer_id === ip || message.peer_id === 'manual_' + ip);
  }
  function normalize(message) {
    const result = {...message};
    if (!result.attachment && result.file_name) result.attachment = {
      name:result.file_name, size:result.file_size, type:result.kind || 'file', status:result.status, progress:100
    };
    return result;
  }
  function merge(local, server) {
    const result = new Map();
    for (const msg of local || []) {
      if (msg.is_wan || msg.is_p2p || !msg._serverSynced || ['Queued','Sending'].includes(msg.status)) result.set(msg.id, msg);
    }
    for (const msg of server || []) result.set(msg.id, {...result.get(msg.id), ...normalize(msg), _serverSynced:true});
    return [...result.values()].sort((a,b) => new Date(a.at) - new Date(b.at));
  }
  const api = {canonical, learn, resolve, matches, normalize, merge};
  if (typeof module !== 'undefined') module.exports = api;
  root.NearMitraChat = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
