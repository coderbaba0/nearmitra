import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../services/nearby_service.dart';
import '../services/wireless_audio_service.dart';
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
        await widget.service.wirelessAudio.requestDeviceAudio(peer);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _section(BuildContext context, String title, Widget child) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable:
            Listenable.merge([widget.service, widget.service.wirelessAudio]),
        builder: (context, _) {
          final audio = widget.service.wirelessAudio;
          final microphone = audio.session == null
              ? _microphone
              : audio.session!.source == 'mic' &&
                  (audio.session!.sending ||
                      (audio.session!.pending && audio.session!.offer == null));
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
          final selectedPhone = ['android', 'ios']
              .contains(peers[selected]?.platform?.toLowerCase());
          final actions = <Widget>[
            if (audio.needsApproval) ...[
              FilledButton.icon(
                onPressed: audio.approve,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Allow audio'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: audio.decline, child: const Text('Decline')),
            ] else if (audio.busy) ...[
              if (audio.session?.sending == true &&
                  audio.session?.phonePcm != true) ...[
                OutlinedButton.icon(
                  onPressed: audio.toggleMute,
                  icon: Icon(
                      audio.muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                  label: Text(
                      audio.muted ? 'Unmute microphone' : 'Mute microphone'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.tonalIcon(
                onPressed: () => audio.stop(),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop wireless audio'),
              ),
            ] else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16)),
                onPressed: selected == null || widget.otherStreamActive
                    ? null
                    : () => _start(peers[selected]),
                icon: Icon(
                    microphone ? Icons.mic_rounded : Icons.headphones_rounded),
                label: Text(microphone
                    ? 'Share phone microphone'
                    : selectedPhone
                        ? 'Listen to phone audio'
                        : 'Listen to PC audio'),
              ),
          ];
          return ColoredBox(
            color: colors.surface,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(children: [
                  Expanded(
                      child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.graphic_eq_rounded,
                              color: colors.onPrimaryContainer, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Wi-Fi Audio',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text('Audio between your devices',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: colors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ]),
                      if (audio.session?.live == true) ...[
                        const SizedBox(height: 16),
                        _AudioSessionCard(
                            audio: audio,
                            peer: peers[selected],
                            microphone: microphone),
                      ] else if (audio.busy ||
                          audio.status != 'Ready for wireless audio') ...[
                        const SizedBox(height: 16),
                        Row(children: [
                          Icon(
                              audio.needsApproval
                                  ? Icons.verified_user_outlined
                                  : Icons.info_outline_rounded,
                              size: 20,
                              color: colors.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(audio.status)),
                        ]),
                      ],
                      if (audio.session?.live == true &&
                          audio.session?.sending == false) ...[
                        const SizedBox(height: 16),
                        _section(
                            context,
                            'Playback',
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Icon(Icons.volume_up_rounded,
                                      color: colors.onSurfaceVariant, size: 20),
                                  const SizedBox(width: 10),
                                  const Expanded(child: Text('Volume')),
                                  Text('${(audio.volume * 100).round()}%',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge),
                                ]),
                                Slider(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  value: audio.volume,
                                  onChanged: audio.setVolume,
                                  label: '${(audio.volume * 100).round()}%',
                                  semanticFormatterCallback: (value) =>
                                      '${(value * 100).round()} percent',
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('wireless-output-toggle'),
                                  onPressed: audio.routingOutput
                                      ? null
                                      : () => audio.setPhoneSpeaker(
                                          !audio.speakerEnabled),
                                  icon: audio.routingOutput
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Icon(audio.speakerEnabled
                                          ? Icons.hearing_rounded
                                          : Icons.volume_up_rounded),
                                  label: Text(audio.routingOutput
                                      ? 'Switching output…'
                                      : audio.speakerEnabled
                                          ? 'Use earpiece'
                                          : 'Use speaker'),
                                ),
                                if (audio.outputStatus
                                    .contains('could not change'))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(audio.outputStatus,
                                        style: TextStyle(color: colors.error)),
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                    audio.session!.phonePcm
                                        ? "Use your phone's media-volume buttons. Some apps do not allow audio capture."
                                        : "Use your phone's call-volume buttons for this stream.",
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: colors.onSurfaceVariant)),
                                if (audio.bufferDelayMs != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                      'Playback buffer: ${audio.bufferDelayMs!.round()} ms',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: colors.onSurfaceVariant)),
                                ],
                              ],
                            )),
                      ],
                      if (audio.session?.live != true) ...[
                        const SizedBox(height: 16),
                        _section(
                            context,
                            'Connection',
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SegmentedButton<bool>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                        value: false,
                                        label: Text('Listen'),
                                        icon: Icon(Icons.headphones_rounded)),
                                    ButtonSegment(
                                        value: true,
                                        label: Text('Share mic'),
                                        icon: Icon(Icons.mic_rounded)),
                                  ],
                                  selected: {microphone},
                                  onSelectionChanged: audio.busy
                                      ? null
                                      : (value) => setState(
                                          () => _microphone = value.first),
                                ),
                                const SizedBox(height: 20),
                                DropdownButtonFormField<String>(
                                  key: ValueKey(selected),
                                  initialValue: selected,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Nearby device',
                                    prefixIcon: Icon(selectedPhone
                                        ? Icons.phone_android_rounded
                                        : Icons.computer_rounded),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                  items: peers.entries
                                      .map((entry) => DropdownMenuItem(
                                            value: entry.key,
                                            child: Text(
                                                '${entry.value.name} · ${entry.key}',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: audio.busy
                                      ? null
                                      : (value) => setState(() {
                                            _target = value;
                                            _retainedPeer = peers[value];
                                          }),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                    microphone
                                        ? "Share this phone's microphone with the selected device. Its owner must approve playback."
                                        : selectedPhone
                                            ? "Listen to the other phone's music, video and app audio. Its owner must approve audio capture. Requires Android 10+ and apps that allow playback capture."
                                            : 'Listen to PC music or video on this phone. On Windows, approve the request and select Share audio.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                            height: 1.5)),
                              ],
                            )),
                      ],
                      const SizedBox(height: 20),
                      if (peers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Connect a Nearby / P2P device first. WAN-only devices are not supported.'),
                        ),
                      if (widget.otherStreamActive)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Stop the other live stream before starting wireless audio.'),
                        ),
                      const SizedBox(height: 20),
                      Text(
                          'New sessions need permission on the other device. Either device can stop audio.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: colors.onSurfaceVariant, height: 1.5)),
                      if (microphone && !selectedPhone) ...[
                        const SizedBox(height: 12),
                        Text(
                            'To use the shared microphone in other Windows apps, a virtual audio device is required.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ],
                  )),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border:
                          Border(top: BorderSide(color: colors.outlineVariant)),
                    ),
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: actions,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

class _AudioSessionCard extends StatelessWidget {
  const _AudioSessionCard({
    required this.audio,
    required this.peer,
    required this.microphone,
  });

  final WirelessAudioService audio;
  final Peer? peer;
  final bool microphone;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF72E6C4);
    final level =
        audio.audioLevel.isFinite ? audio.audioLevel.clamp(0, 1) : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172B35), Color(0xFF123A38)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(microphone ? Icons.mic_rounded : Icons.headphones_rounded,
                size: 19, color: accent),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    audio.session?.sending == true
                        ? 'Sharing audio'
                        : 'Live playback',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            const Icon(Icons.circle, size: 6, color: accent),
            const SizedBox(width: 5),
            const Text('LIVE',
                style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 6),
          Text(peer?.name ?? 'Nearby device',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB1C6CA), fontSize: 12)),
          const SizedBox(height: 8),
          WirelessAudioMeter(
            level: audio.audioLevel,
            active: true,
            color: accent,
            idleColor: const Color(0xFF36525B),
            height: 52,
          ),
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(
                child: Text('LIVE SIGNAL',
                    style: TextStyle(
                        color: Color(0xFFB1C6CA),
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600))),
            Text('${(level * 100).round()}%',
                style: const TextStyle(color: accent, fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}
