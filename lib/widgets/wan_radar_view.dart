import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/wan_models.dart';

class WanRadarView extends StatefulWidget {
  final List<WanDevice> devices;
  final Function(WanDevice) onDeviceSelected;
  final VoidCallback onPairCodePressed;
  final bool isOnline;
  final bool isFirebaseConnected;
  final bool isInternetModeOn;
  final String? currentDeviceId;
  final String? currentDeviceName;

  final Function(WanDevice)? onUnpairDevice;

  const WanRadarView({
    super.key,
    required this.devices,
    required this.onDeviceSelected,
    required this.onPairCodePressed,
    required this.isOnline,
    this.isFirebaseConnected = false,
    this.isInternetModeOn = true,
    this.currentDeviceId,
    this.currentDeviceName,
    this.onUnpairDevice,
  });

  @override
  State<WanRadarView> createState() => _WanRadarViewState();
}

class _WanRadarViewState extends State<WanRadarView> with TickerProviderStateMixin {
  late AnimationController _radarController;
  late AnimationController _earthRotationController;
  Timer? _connectivityTimer;
  bool _hasInternet = false;

  @override
  void initState() {
    super.initState();
    _hasInternet = widget.isOnline || widget.isFirebaseConnected;
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _earthRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    );

    if (_hasInternet) {
      _radarController.repeat();
      _earthRotationController.repeat();
    }

    _checkInternetConnectivity();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkInternetConnectivity();
    });
  }

  @override
  void didUpdateWidget(covariant WanRadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline != oldWidget.isOnline ||
        widget.isFirebaseConnected != oldWidget.isFirebaseConnected ||
        widget.isInternetModeOn != oldWidget.isInternetModeOn) {
      _checkInternetConnectivity();
    }
  }

  Future<void> _checkInternetConnectivity() async {
    bool online = false;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(milliseconds: 1500));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        online = true;
      }
    } catch (_) {
      online = widget.isOnline || widget.isFirebaseConnected;
    }

    if (!mounted) return;

    if (_hasInternet != online) {
      setState(() {
        _hasInternet = online;
        if (_hasInternet && widget.isInternetModeOn) {
          if (!_radarController.isAnimating) {
            _radarController.repeat();
          }
          if (!_earthRotationController.isAnimating) {
            _earthRotationController.repeat();
          }
        } else {
          if (_radarController.isAnimating) {
            _radarController.stop();
            _radarController.reset();
          }
          if (_earthRotationController.isAnimating) {
            _earthRotationController.stop();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _radarController.dispose();
    _earthRotationController.dispose();
    super.dispose();
  }

  Offset _getNodeOffset(int index, int total, double radius) {
    if (total == 0) return Offset.zero;
    final angle = (index * (2 * math.pi / math.max(total, 4))) - (math.pi / 2);
    final distance = radius * 0.68;
    return Offset(
      math.cos(angle) * distance,
      math.sin(angle) * distance,
    );
  }

  int _compareDevices(WanDevice a, WanDevice b) {
    final aOnline = (_hasInternet && a.isOnline) ? 1 : 0;
    final bOnline = (_hasInternet && b.isOnline) ? 1 : 0;
    if (aOnline != bOnline) {
      return bOnline.compareTo(aOnline); // Online always on top
    }
    final aUnread = a.unreadCount;
    final bUnread = b.unreadCount;
    if (aUnread != bUnread) {
      return bUnread.compareTo(aUnread); // Unread messages on top
    }
    final aName = a.name.toLowerCase();
    final bName = b.name.toLowerCase();
    return aName.compareTo(bName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isLive = _hasInternet && widget.isInternetModeOn && (widget.isFirebaseConnected || widget.isOnline);
    final statusTitle = !_hasInternet
        ? 'No Internet Connection'
        : (widget.isInternetModeOn
            ? (widget.isFirebaseConnected ? 'Internet Mode Enabled' : 'Connecting to Server…')
            : 'Internet Mode Disabled');
    final statusSubtitle = !_hasInternet
        ? 'Connect to Wi-Fi or mobile data for WAN Mesh'
        : (widget.isInternetModeOn
            ? (widget.isFirebaseConnected
                ? 'Server Connected • ${widget.currentDeviceName ?? "This Device"}'
                : 'Connecting to Cloud Mesh…')
            : 'Switch to WAN Mesh to go online');

    final sortedDevices = List<WanDevice>.from(widget.devices)..sort(_compareDevices);
    final onlineCount = sortedDevices.where((d) => _hasInternet && d.isOnline).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // UNIFIED TOP STATUS & PAIR CARD
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive
                  ? const Color(0xFF10B981).withValues(alpha: 0.35)
                  : (_hasInternet && widget.isInternetModeOn
                      ? Colors.amber.withValues(alpha: 0.35)
                      : (isDark ? Colors.white12 : Colors.black12)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isLive
                          ? const Color(0xFF10B981)
                          : (_hasInternet && widget.isInternetModeOn ? Colors.amber : Colors.grey))
                      .withValues(alpha: 0.15),
                ),
                child: Icon(
                  _hasInternet ? Icons.public_rounded : Icons.public_off_rounded,
                  color: isLive
                      ? const Color(0xFF10B981)
                      : (_hasInternet && widget.isInternetModeOn ? Colors.amber : Colors.grey),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isLive ? (isDark ? Colors.white70 : Colors.black54) : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _hasInternet ? widget.onPairCodePressed : null,
                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                label: const Text('Pair', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF005C4B),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),

        // Interactive Radar Circle
        SizedBox(
          height: 205,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.92;
              final centerOffset = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
              final radarRadius = size / 2;

              return Stack(
                alignment: Alignment.center,
                children: [
                  // Sweep Painter
                  AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: Size(size, size),
                        painter: _WanRadarPainter(
                          progress: _hasInternet ? _radarController.value : 0.0,
                          isDark: isDark,
                          hasInternet: _hasInternet,
                        ),
                      );
                    },
                  ),

                  // Orbiting Peer Nodes on Radar (Compact & Sleek)
                  for (int i = 0; i < widget.devices.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final dev = widget.devices[i];
                        final nodeOffset = _getNodeOffset(i, widget.devices.length, radarRadius);
                        final posX = centerOffset.dx + nodeOffset.dx;
                        final posY = centerOffset.dy + nodeOffset.dy;
                        final isPeerOnline = _hasInternet && dev.isOnline;

                        return Positioned(
                          left: posX - 20,
                          top: posY - 20,
                          child: GestureDetector(
                            onTap: () => widget.onDeviceSelected(dev),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isPeerOnline
                                        ? const Color(0xFF10B981)
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                    border: Border.all(
                                      color: isPeerOnline ? Colors.white : (isDark ? Colors.white24 : Colors.grey.shade400),
                                      width: 1.5,
                                    ),
                                    boxShadow: isPeerOnline
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                                              blurRadius: 8,
                                              spreadRadius: 1.5,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Icon(
                                    dev.platform == 'windows' ? Icons.laptop_windows_rounded : Icons.smartphone_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  constraints: const BoxConstraints(maxWidth: 62),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    dev.name,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],

                  // Center Host Icon (Transparent without dark background circle)
                  Center(
                    child: _hasInternet
                        ? RotationTransition(
                            turns: _earthRotationController,
                            child: const Icon(
                              Icons.public_rounded,
                              color: Color(0xFF10B981),
                              size: 26,
                            ),
                          )
                        : Icon(
                            Icons.public_off_rounded,
                            color: isDark ? Colors.white38 : Colors.grey,
                            size: 26,
                          ),
                  ),
                ],
              );
            },
          ),
        ),

        // Helper text below radar indicating internet usage
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _hasInternet ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                size: 12,
                color: _hasInternet ? const Color(0xFF10B981) : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                _hasInternet
                    ? 'Internet Mesh Active • End-to-End P2P'
                    : 'Offline • Connect internet for WAN',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: _hasInternet
                      ? (isDark ? Colors.white60 : Colors.black54)
                      : (isDark ? Colors.white38 : Colors.black45),
                ),
              ),
            ],
          ),
        ),

        // Section Title with Online Counter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Row(
            children: [
              Text(
                'PAIRED INTERNET PEERS (${sortedDevices.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              if (sortedDevices.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: onlineCount > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: onlineCount > 0 ? const Color(0xFF10B981) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$onlineCount Online',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: onlineCount > 0
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Device Cards List (Scrollable & Prioritizing Online Peers)
        Expanded(
          child: Builder(
            builder: (context) {
              if (sortedDevices.isEmpty) {
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices_other_rounded, size: 28, color: isDark ? Colors.white30 : Colors.black26),
                        const SizedBox(height: 6),
                        Text(
                          'No Paired Internet Devices',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1. Tap "Pair" above to generate 6-digit code.\n'
                          '2. On other device, tap "Pair" & enter code.\n'
                          '3. Tap "Accept" to pair devices permanently.\n'
                          '4. Tap on device card to open chat & share files.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 8),
                physics: const BouncingScrollPhysics(),
                itemCount: sortedDevices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final device = sortedDevices[index];
                  final isPeerOnline = _hasInternet && device.isOnline;

                  return Material(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onDeviceSelected(device),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPeerOnline
                                ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                : (isDark ? const Color(0xFF2A3942) : const Color(0xFFE2E8F0)),
                            width: isPeerOnline ? 1.2 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isPeerOnline
                                  ? const Color(0xFF10B981).withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Device Icon with Live Status Dot
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isPeerOnline
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                                  ),
                                  child: Icon(
                                    device.platform == 'windows' ? Icons.laptop_windows_rounded : Icons.smartphone_rounded,
                                    color: isPeerOnline ? const Color(0xFF10B981) : Colors.grey,
                                    size: 19,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isPeerOnline ? const Color(0xFF10B981) : Colors.grey.shade500,
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),

                            // Device Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          device.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          device.platform == 'windows' ? 'PC' : 'Mobile',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isPeerOnline
                                        ? 'Online • Tap to Open'
                                        : (device.lastSeen != null
                                            ? 'Offline • Last seen ${device.lastSeen!.hour}:${device.lastSeen!.minute.toString().padLeft(2, '0')}'
                                            : 'Offline • Tap to Open'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isPeerOnline ? FontWeight.w500 : FontWeight.normal,
                                      color: isPeerOnline ? const Color(0xFF10B981) : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 4),

                            // Unread Message Badge Count (Green WhatsApp Style)
                            if (device.unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                child: Center(
                                  child: Text(
                                    device.unreadCount > 99 ? '99+' : '${device.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ),

                            // 3-Dot Options Menu
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                              tooltip: 'Options',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              elevation: 3,
                              onSelected: (value) {
                                if (value == 'chat') {
                                  widget.onDeviceSelected(device);
                                } else if (value == 'unpair') {
                                  widget.onUnpairDevice?.call(device);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'chat',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFF10B981)),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Open',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.onUnpairDevice != null)
                                  PopupMenuItem(
                                    value: 'unpair',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Unpair Device',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.redAccent.shade200,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WanRadarPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final bool hasInternet;

  _WanRadarPainter({
    required this.progress,
    required this.isDark,
    required this.hasInternet,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final primaryColor = hasInternet ? const Color(0xFF10B981) : Colors.grey;

    final ringPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDark ? (hasInternet ? 0.15 : 0.10) : (hasInternet ? 0.22 : 0.15))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Concentric rings
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3), ringPaint);
    }

    // Crosshairs
    final crossPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDark ? (hasInternet ? 0.08 : 0.05) : (hasInternet ? 0.12 : 0.08))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), crossPaint);
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), crossPaint);

    if (!hasInternet) {
      // Offline mode: static grey radar layout without sweep or pulsing waves
      return;
    }

    // Expanding pulse waves
    for (int i = 0; i < 2; i++) {
      final waveProgress = (progress + (i * 0.5)) % 1.0;
      final waveRadius = maxRadius * waveProgress;
      final waveOpacity = (1.0 - waveProgress).clamp(0.0, 1.0) * 0.35;

      final wavePaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: waveOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // Rotating sweep gradient
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.0),
          const Color(0xFF10B981).withValues(alpha: 0.28),
        ],
        stops: const [0.75, 1.0],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _WanRadarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.hasInternet != hasInternet ||
        oldDelegate.isDark != isDark;
  }
}
