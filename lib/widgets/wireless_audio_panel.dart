import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../services/nearby_service.dart';
import 'wireless_audio_meter.dart';

class WirelessAudioPanel extends StatefulWidget {
  const WirelessAudioPanel(
      {super.key,
      required this.service,
      this.targetPeer,
      this.otherStreamActive = false});
  final NearbyService service;
  final Peer? targetPeer;
  final bool otherStreamActive;
  @override
  State<WirelessAudioPanel> createState() => _WirelessAudioPanelState();
}

class _WirelessAudioPanelState extends State<WirelessAudioPanel> {
  String? _target;
  Peer? _retainedPeer;
  bool _microphone = false;
  @override
  void initState() {
    super.initState();
    _target = widget.targetPeer?.ip;
    _retainedPeer = widget.targetPeer;
  }

  Future<void> _start(Peer? peer) async {
    if (peer == null) return;
    try {
      if (_microphone) {
        await widget.service.wirelessAudio.sendMicrophone(peer);
      } else {
        await widget.service.wirelessAudio.requestPcAudio(peer);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable:
            Listenable.merge([widget.service, widget.service.wirelessAudio]),
        builder: (context, _) {
          final audio = widget.service.wirelessAudio;
          final microphone = audio.session == null
              ? _microphone
              : audio.session!.sending ||
                  (audio.session!.pending && audio.session!.offer == null);
          final colors = Theme.of(context).colorScheme;
          final peers = <String, Peer>{};
          for (final peer in widget.service.peers) {
            if (peer.ip.isNotEmpty && !peer.isMeshPeer) {
              peers[peer.ip] = peer;
            }
          }
          if (_retainedPeer != null && _retainedPeer!.ip == _target) {
            peers.putIfAbsent(_target!, () => _retainedPeer!);
          }
          final initialPeer = widget.targetPeer;
          if (initialPeer != null &&
              initialPeer.ip.isNotEmpty &&
              !initialPeer.isMeshPeer) {
            peers.putIfAbsent(initialPeer.ip, () => initialPeer);
          }
          final activePeer = audio.session?.peer;
          if (activePeer != null) peers[activePeer.ip] = activePeer;
          _target ??= peers.keys.firstOrNull;
          _retainedPeer = peers[_target] ?? _retainedPeer;
          final selected =
              activePeer?.ip ?? (peers.containsKey(_target) ? _target : null);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Icon(microphone ? Icons.mic_rounded : Icons.spatial_audio_rounded,
                  size: 52, color: colors.primary),
              const SizedBox(height: 16),
              Text('Wi-Fi Audio',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                  'Live audio over Nearby / Wi-Fi Direct. No phone call or camera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Speaker'),
                      icon: Icon(Icons.speaker_rounded)),
                  ButtonSegment(
                      value: true,
                      label: Text('Mic'),
                      icon: Icon(Icons.mic_rounded))
                ],
                selected: {microphone},
                onSelectionChanged: audio.busy
                    ? null
                    : (value) => setState(() => _microphone = value.first),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nearby device'),
                items: peers.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.value.name} · ${e.key}',
                            maxLines: 1, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: audio.busy
                    ? null
                    : (value) => setState(() {
                          _target = value;
                          _retainedPeer = peers[value];
                        }),
              ),
              const SizedBox(height: 16),
              Text(microphone
                  ? 'Send this phone’s microphone to the selected PC or phone. The other device must approve playback.'
                  : 'Use this phone as a speaker for PC music or YouTube. On Windows, approve the request and select Share audio.'),
              const SizedBox(height: 20),
              Card(
                color: colors.surfaceContainerLow,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      WirelessAudioMeter(
                          level: audio.audioLevel,
                          active: audio.session?.live == true),
                      const SizedBox(height: 14),
                      Row(children: [
                        Icon(
                            audio.session?.live == true
                                ? Icons.graphic_eq_rounded
                                : Icons.info_outline_rounded,
                            color: colors.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text(audio.status))
                      ]),
                      if (audio.session != null) ...[
                        const SizedBox(height: 10),
                        Text(
                            audio.session!.sending
                                ? 'This phone is sharing its microphone'
                                : 'This phone receives audio; its microphone stays off',
                            style: TextStyle(color: colors.onSurfaceVariant)),
                      ],
                      if (audio.session?.live == true &&
                          audio.session?.sending == false) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            onPressed: audio.routingOutput
                                ? null
                                : () => audio
                                    .setPhoneSpeaker(!audio.speakerEnabled),
                            icon: Icon(audio.speakerEnabled
                                ? Icons.hearing_rounded
                                : Icons.volume_up_rounded),
                            label: Text(audio.routingOutput
                                ? 'Switching output…'
                                : audio.speakerEnabled
                                    ? 'Use earpiece'
                                    : 'Use phone speaker')),
                        Text(audio.outputStatus,
                            style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w600)),
                        if (audio.bufferDelayMs != null)
                          Text(
                              'Playback buffer: ${audio.bufferDelayMs!.round()} ms',
                              style: Theme.of(context).textTheme.bodySmall),
                        Text(
                            'Use the phone’s call-volume buttons for this WebRTC stream.',
                            style: Theme.of(context).textTheme.bodySmall),
                        Row(children: [
                          const Icon(Icons.volume_up_rounded),
                          Expanded(
                              child: Slider(
                                  value: audio.volume,
                                  onChanged: (value) => audio.setVolume(value),
                                  label: '${(audio.volume * 100).round()}%'))
                        ]),
                      ],
                    ])),
              ),
              const SizedBox(height: 16),
              if (audio.needsApproval) ...[
                FilledButton.icon(
                    onPressed: audio.approve,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Allow audio')),
                OutlinedButton(
                    onPressed: audio.decline, child: const Text('Decline')),
                const SizedBox(height: 12),
              ],
              if (audio.busy) ...[
                if (audio.session?.sending == true)
                  OutlinedButton.icon(
                      onPressed: audio.toggleMute,
                      icon: Icon(audio.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded),
                      label: Text(audio.muted
                          ? 'Unmute microphone'
                          : 'Mute microphone')),
                FilledButton.tonalIcon(
                    onPressed: () => audio.stop(),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop wireless audio')),
              ] else
                FilledButton.icon(
                  onPressed: selected == null || widget.otherStreamActive
                      ? null
                      : () => _start(peers[selected]),
                  icon: Icon(
                      microphone ? Icons.mic_rounded : Icons.speaker_rounded),
                  label: Text(microphone
                      ? 'Share phone microphone'
                      : 'Listen to PC audio'),
                ),
              if (peers.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                        'Connect a Nearby / P2P device first. WAN-only devices are not supported.')),
              if (widget.otherStreamActive)
                const Text(
                    'Stop the other live stream before starting wireless audio.'),
              const SizedBox(height: 24),
              Text(
                  'Microphone audio plays in NearMitra on the PC. Using it as a microphone input in other Windows apps requires a virtual audio device. Keep NearMitra open to approve a new request.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
          );
        },
      );
}
