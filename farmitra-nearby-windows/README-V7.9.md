# Farmitra Nearby v7.9 — Bidirectional People Chat Stability

This release fixes a Windows-side regression where desktop -> Android People chat could work while Android -> desktop messages were not visible in the selected conversation.

## Fixes
- Self-recovering inbound TCP server on `0.0.0.0:43889`.
- Incoming peer identity is resolved against the existing sidebar peer using persistent ID first and remote IP as a compatibility fallback.
- Accepts common Android/Flutter sender field aliases (`sender_id`, `senderId`, `device_id`, `deviceId`, etc.).
- Incoming chat, typing and received-file events are attached to the canonical peer conversation.
- Incoming messages for the conversation currently open in People mode no longer create a false unread badge.
- Existing v7.8 scrollable nearby-device list, green online state, P2P radar, clipboard transfer, Nearby AI, Local AI, provider settings, About dialog and larger embedded taskbar icon are retained.

## Protocol
- UDP 43888: discovery
- TCP 43889: chat, file, typing and Nearby AI transport
