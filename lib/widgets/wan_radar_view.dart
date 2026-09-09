import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/wan_models.dart';
import '../services/wan_service.dart';

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
  final WanService _wanService = WanService();
  bool _isSendingRequest = false;
  String? _connectingPeerId;

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
    // 1. Trusted devices first
    if (a.isTrusted != b.isTrusted) {
      return a.isTrusted ? -1 : 1;
    }
    // 2. Online devices first
    final aOnline = (_hasInternet && a.isOnline) ? 1 : 0;
    final bOnline = (_hasInternet && b.isOnline) ? 1 : 0;
    if (aOnline != bOnline) {
      return bOnline.compareTo(aOnline);
    }
    // 3. Unread count
    final aUnread = a.unreadCount;
    final bUnread = b.unreadCount;
    if (aUnread != bUnread) {
      return bUnread.compareTo(aUnread);
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _showDirectPairConfirmDialog(WanDevice target) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFF10B981), width: 2),
                      ),
                      child: Icon(
                        target.platform == 'windows' ? Icons.laptop_windows_rounded : Icons.smartphone_rounded,
                        color: const Color(0xFF10B981),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Connect to ${target.name}?',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This device was discovered live on WAN Radar. Send a 1-tap connection request to start chatting and sharing files.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white70 : Colors.black54,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSendingRequest ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _isSendingRequest
                                ? null
                                : () async {
                                    setModalState(() => _isSendingRequest = true);
                                    setState(() {
                                      _isSendingRequest = true;
                                      _connectingPeerId = target.id;
                                    });
                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      Navigator.pop(ctx);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(child: Text('Sending request to ${target.name}…')),
                                            ],
                                          ),
                                          duration: const Duration(seconds: 40),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );

                                      final paired = await _wanService.sendDirectPairRequest(target);
                                      if (!mounted) return;
                                      messenger.removeCurrentSnackBar();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('Connected with ${paired.name}!'),
                                          backgroundColor: const Color(0xFF005C4B),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      widget.onDeviceSelected(paired);
                                    } catch (e) {
                                      if (!mounted) return;
                                      messenger.removeCurrentSnackBar();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString().replaceFirst('Exception: ', '')),
                                          backgroundColor: Colors.redAccent,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isSendingRequest = false;
                                          _connectingPeerId = null;
                                        });
                                      }
                                    }
                                  },
                            icon: _isSendingRequest
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(_isSendingRequest ? 'Sending…' : 'Send Request'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF005C4B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showPrivacyModeSelector() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.security_rounded, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'WAN Discovery & Privacy Mode',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 1. Public Radar Mode
                _discoveryModeOption(
                  mode: WanDiscoveryMode.publicRadar,
                  icon: Icons.public_rounded,
                  title: 'Public Radar Mode',
                  subtitle: 'Visible to everyone online on WAN Radar for quick 1-tap connection requests.',
                  color: const Color(0xFF10B981),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _wanService.setDiscoveryMode(WanDiscoveryMode.publicRadar);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),

                // 2. Ghost / Private Mode
                _discoveryModeOption(
                  mode: WanDiscoveryMode.privateGhost,
                  icon: Icons.visibility_off_rounded,
                  title: 'Ghost / Private Mode',
                  subtitle: 'Hidden from the public radar. Only previously paired trusted friends can connect.',
                  color: const Color(0xFF6366F1),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _wanService.setDiscoveryMode(WanDiscoveryMode.privateGhost);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),

                // 3. PIN Code Only
                _discoveryModeOption(
                  mode: WanDiscoveryMode.pinOnly,
                  icon: Icons.pin_rounded,
                  title: 'PIN Code Only',
                  subtitle: 'Hidden from radar. New devices must enter your 6-digit pair PIN code to connect.',
                  color: const Color(0xFFF59E0B),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _wanService.setDiscoveryMode(WanDiscoveryMode.pinOnly);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _discoveryModeOption({
    required WanDiscoveryMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _wanService.discoveryMode == mode;

    return Material(
      color: isSelected
          ? color.withValues(alpha: isDark ? 0.18 : 0.10)
          : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : (isDark ? Colors.white10 : Colors.black12),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.2),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: isSelected ? color : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: color, size: 18),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }  bool _isEmoji(String char) {
    if (char.isEmpty) return false;
    return char.runes.any((r) =>
        (r >= 0x1F300 && r <= 0x1F9FF) ||
        (r >= 0x2600 && r <= 0x27BF) ||
        (r >= 0x1FA70 && r <= 0x1FAFF) ||
        (r >= 0xFE00 && r <= 0xFE0F) ||
        (r >= 0x1F000 && r <= 0x1F2FF));
  }

  Widget _buildPeerLeadingAvatar(WanDevice device, bool isPeerOnline, bool isTrusted, bool isDark) {
    final emoji = (device.avatarEmoji != null && device.avatarEmoji!.trim().isNotEmpty)
        ? device.avatarEmoji!.trim()
        : (_isEmoji(device.name.trim().characters.firstOrNull ?? '') ? device.name.trim().characters.first : null);

    if (emoji != null && emoji.isNotEmpty) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isTrusted
              ? (isPeerOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)))
              : const Color(0xFF0EA5E9).withValues(alpha: 0.15),
          border: Border.all(
            color: isTrusted
                ? (isPeerOnline ? const Color(0xFF10B981) : Colors.transparent)
                : const Color(0xFF0EA5E9),
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isTrusted
            ? (isPeerOnline
                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)))
            : const Color(0xFF0EA5E9).withValues(alpha: 0.15),
      ),
      child: Icon(
        device.platform == 'windows' ? Icons.laptop_windows_rounded : Icons.smartphone_rounded,
        color: isTrusted
            ? (isPeerOnline ? const Color(0xFF10B981) : Colors.grey)
            : const Color(0xFF0EA5E9),
        size: 19,
      ),
    );
  }

  Widget _buildRadarNodeIcon(WanDevice dev) {
    final emoji = (dev.avatarEmoji != null && dev.avatarEmoji!.trim().isNotEmpty)
        ? dev.avatarEmoji!.trim()
        : (_isEmoji(dev.name.trim().characters.firstOrNull ?? '') ? dev.name.trim().characters.first : null);

    if (emoji != null && emoji.isNotEmpty) {
      return Text(emoji, style: const TextStyle(fontSize: 13));
    }
    return Icon(
      dev.platform == 'windows' ? Icons.laptop_windows_rounded : Icons.smartphone_rounded,
      color: Colors.white,
      size: 14,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isLive = _hasInternet && widget.isInternetModeOn && (widget.isFirebaseConnected || widget.isOnline);
    final currentMode = _wanService.discoveryMode;

    final modeLabel = currentMode == WanDiscoveryMode.publicRadar
        ? 'Public'
        : (currentMode == WanDiscoveryMode.privateGhost ? 'Ghost' : 'PIN');
    final modeIcon = currentMode == WanDiscoveryMode.publicRadar
        ? Icons.public_rounded
        : (currentMode == WanDiscoveryMode.privateGhost ? Icons.visibility_off_rounded : Icons.pin_rounded);

    final statusTitle = !_hasInternet
        ? 'No Internet Connection'
        : (widget.isInternetModeOn
            ? (widget.isFirebaseConnected ? 'Internet Mesh Active' : 'Connecting to Server…')
            : 'Internet Mode Disabled');
    final statusSubtitle = !_hasInternet
        ? 'Connect to Wi-Fi or mobile data for WAN'
        : (widget.isInternetModeOn
            ? (widget.isFirebaseConnected
                ? '${widget.currentDeviceName ?? "This Device"} • $modeLabel Mode'
                : 'Connecting to Cloud Mesh…')
            : 'Switch to WAN Mesh to go online');

    final activeDevices = widget.devices.where((d) => _hasInternet && d.isOnline).toList();
    final sortedDevices = List<WanDevice>.from(widget.devices)..sort(_compareDevices);
    final onlineCount = sortedDevices.where((d) => _hasInternet && d.isOnline).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TOP STATUS & PAIR CARD WITH QUICK PRIVACY MODE CHIP
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.fromLTRB(4, 2, 4, 8),
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
                width: 34,
                height: 34,
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
                  size: 19,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      statusSubtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isLive ? (isDark ? Colors.white70 : Colors.black54) : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Privacy Mode Chip Button
              InkWell(
                onTap: _showPrivacyModeSelector,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentMode == WanDiscoveryMode.publicRadar
                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                          : (isDark ? Colors.white24 : Colors.black26),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        modeIcon,
                        size: 13,
                        color: currentMode == WanDiscoveryMode.publicRadar
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        modeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: currentMode == WanDiscoveryMode.publicRadar
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Pair PIN / QR Button
              Material(
                color: const Color(0xFF005C4B),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _hasInternet ? widget.onPairCodePressed : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Pair',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Interactive Radar Circle
        SizedBox(
          height: 200,
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

                  // Orbiting Peer Nodes on Radar
                  for (int i = 0; i < activeDevices.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final dev = activeDevices[i];
                        final nodeOffset = _getNodeOffset(i, activeDevices.length, radarRadius);
                        final posX = centerOffset.dx + nodeOffset.dx;
                        final posY = centerOffset.dy + nodeOffset.dy;
                        final isTrusted = dev.isTrusted;
                        final nodeColor = isTrusted ? const Color(0xFF10B981) : const Color(0xFF0EA5E9);

                        return Positioned(
                          left: posX - 16,
                          top: posY - 16,
                          child: GestureDetector(
                            onTap: () {
                              if (isTrusted) {
                                widget.onDeviceSelected(dev);
                              } else {
                                _showDirectPairConfirmDialog(dev);
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: nodeColor,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: nodeColor.withValues(alpha: 0.6),
                                        blurRadius: 8,
                                        spreadRadius: 1.5,
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: _buildRadarNodeIcon(dev),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  constraints: const BoxConstraints(maxWidth: 66),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    dev.name,
                                    style: TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.bold,
                                      color: nodeColor,
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

                  // Center Host Icon
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

        // Status bar below radar
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _hasInternet ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                size: 12,
                color: _hasInternet ? const Color(0xFF10B981) : Colors.grey,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _hasInternet
                      ? (activeDevices.isNotEmpty
                          ? '${activeDevices.length} active device${activeDevices.length > 1 ? 's' : ''} on radar'
                          : (currentMode == WanDiscoveryMode.publicRadar
                              ? 'Public Radar Active • Scanning for peers…'
                              : (currentMode == WanDiscoveryMode.privateGhost
                                  ? 'Ghost Mode Active • Visible only to paired'
                                  : 'PIN Only Mode Active • Hidden on radar')))
                      : 'Offline • Connect internet for WAN',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: _hasInternet
                        ? (isDark ? Colors.white60 : Colors.black54)
                        : (isDark ? Colors.white38 : Colors.black45),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Section Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Row(
            children: [
              Text(
                'INTERNET PEERS (${sortedDevices.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              if (onlineCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$onlineCount Online',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Device Cards List
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
                        Icon(Icons.public_off_rounded, size: 28, color: isDark ? Colors.white30 : Colors.black26),
                        const SizedBox(height: 6),
                        Text(
                          'No WAN Peers Found',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Ensure Internet Mode is ON on both devices.\n'
                          '• In Public Radar mode, devices online will appear automatically.\n'
                          '• Or tap "Pair" above to connect directly using a 6-digit PIN code.',
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
                  final isTrusted = device.isTrusted;
                  final isPeerOnline = _hasInternet && device.isOnline;
                  final isConnectingThis = _connectingPeerId == device.id;

                  return Material(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (isTrusted) {
                          widget.onDeviceSelected(device);
                        } else {
                          _showDirectPairConfirmDialog(device);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isTrusted
                                ? (isPeerOnline
                                    ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                    : (isDark ? const Color(0xFF2A3942) : const Color(0xFFE2E8F0)))
                                : const Color(0xFF0EA5E9).withValues(alpha: 0.3),
                            width: isTrusted ? (isPeerOnline ? 1.2 : 1.0) : 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isTrusted
                                  ? (isPeerOnline
                                      ? const Color(0xFF10B981).withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.02))
                                  : const Color(0xFF0EA5E9).withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Device Icon/Avatar
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _buildPeerLeadingAvatar(device, isPeerOnline, isTrusted, isDark),
                                if (isTrusted)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
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
                                          color: isTrusted
                                              ? (isDark ? Colors.white10 : const Color(0xFFF1F5F9))
                                              : const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isTrusted ? (device.platform == 'windows' ? 'PC' : 'Mobile') : 'Public Radar',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: isTrusted
                                                ? (isDark ? Colors.white60 : Colors.black54)
                                                : const Color(0xFF0EA5E9),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isTrusted
                                        ? (isPeerOnline
                                            ? 'Paired • Online'
                                            : (device.lastSeen != null
                                                ? 'Paired • Offline (Last seen ${device.lastSeen!.hour}:${device.lastSeen!.minute.toString().padLeft(2, '0')})'
                                                : 'Paired • Offline'))
                                        : 'Online on Radar • Tap to Connect',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isPeerOnline ? FontWeight.w500 : FontWeight.normal,
                                      color: isTrusted
                                          ? (isPeerOnline ? const Color(0xFF10B981) : Colors.grey)
                                          : const Color(0xFF0EA5E9),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 4),

                            // Unpaired Action Button: Connect
                            if (!isTrusted)
                              FilledButton.tonalIcon(
                                onPressed: _isSendingRequest
                                    ? null
                                    : () => _showDirectPairConfirmDialog(device),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                                  foregroundColor: const Color(0xFF0EA5E9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: isConnectingThis
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFF0EA5E9)),
                                      )
                                    : const Icon(Icons.add_link_rounded, size: 15),
                                label: Text(
                                  isConnectingThis ? 'Connecting…' : 'Connect',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                              ),

                            // Unread Message Badge Count
                            if (isTrusted && device.unreadCount > 0)
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

                            // 3-Dot Options Menu (Open / Unpair)
                            if (isTrusted)
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
                                              color: Colors.redAccent,
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
