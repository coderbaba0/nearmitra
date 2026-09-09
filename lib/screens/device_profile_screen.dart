import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_identity.dart';
import '../services/nearby_service.dart';

class DeviceProfileScreen extends StatefulWidget {
  const DeviceProfileScreen({super.key, required this.service});

  final NearbyService service;

  @override
  State<DeviceProfileScreen> createState() => _DeviceProfileScreenState();
}

class _DeviceProfileScreenState extends State<DeviceProfileScreen> {
  late TextEditingController _nameController;
  late String _selectedEmoji;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.service.deviceName);
    _selectedEmoji = widget.service.avatarEmoji.isNotEmpty
        ? widget.service.avatarEmoji
        : '📱';
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await DeviceIdentity().getId();
    if (mounted) {
      setState(() => _deviceId = id);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF10B981),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _save() async {
    final cleanName = _nameController.text.trim();
    if (cleanName.isEmpty) {
      _toast('Please enter a valid device name');
      return;
    }

    await widget.service.updateDeviceIdentity(
      name: cleanName,
      emoji: _selectedEmoji,
    );

    HapticFeedback.lightImpact();
    _toast('Device profile updated successfully! 🎉');
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('farmitra_nearby_device_name');
    await prefs.remove('farmitra_device_avatar_emoji');

    final defaultName = await DeviceIdentity().getName();
    final defaultEmoji = await DeviceIdentity().getAvatarEmoji();

    setState(() {
      _nameController.text = defaultName;
      _selectedEmoji = defaultEmoji;
    });

    _toast('Reset to default hardware name');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emojiList = DeviceIdentity.presetEmojis;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Device Profile & Avatar',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset to Default',
            icon: const Icon(Icons.restart_alt_rounded, size: 22),
            onPressed: _resetToDefault,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF10B981),
              ),
              onPressed: _save,
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Hero Identity Display Card
            _buildHeroIdentityCard(isDark),

            const SizedBox(height: 24),

            // 2. Device Name Section
            _buildSectionHeader('DEVICE DISPLAY NAME', Icons.badge_outlined),
            const SizedBox(height: 8),
            _buildNameInput(isDark),

            const SizedBox(height: 26),

            // 3. Avatar Emoji Grid Section
            _buildSectionHeader('CHOOSE PROFILE AVATAR EMOJI', Icons.face_rounded),
            const SizedBox(height: 10),

            // Clean Preset Emoji Grid
            _buildEmojiGrid(emojiList, isDark),

            const SizedBox(height: 24),

            // 4. Multi-Network Broadcast Info Card
            _buildNetworkInfoCard(isDark),

            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.of(context).viewInsets.bottom > 0
              ? MediaQuery.of(context).viewInsets.bottom + 12
              : MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _save,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.save_rounded, size: 20),
                SizedBox(width: 8),
                Text(
                  'Save & Broadcast Identity',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroIdentityCard(bool isDark) {
    final displayName = _nameController.text.trim().isEmpty
        ? 'NearMitra Device'
        : _nameController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFE8F5E9), const Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.4 : 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar Bubble with subtle ring
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x3310B981), Colors.transparent],
                  ),
                ),
              ),
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  border: Border.all(
                    color: const Color(0xFF10B981),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  _selectedEmoji,
                  style: const TextStyle(fontSize: 38),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.verified_rounded, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Display Name
          Text(
            displayName,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),

          // Subtitle
          Text(
            'Broadcasting on LAN, P2P & WAN Mesh',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // Protocol Tags
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _buildProtocolTag('📡 Nearby UDP', const Color(0xFF10B981)),
              _buildProtocolTag('⚡ Direct P2P', const Color(0xFF3B82F6)),
              _buildProtocolTag('🌐 Internet WAN', const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF10B981)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Color(0xFF10B981),
          ),
        ),
      ],
    );
  }

  Widget _buildNameInput(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _nameController,
        maxLength: 32,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'e.g. Ramesh Galaxy, Office PC',
          counterText: '',
          prefixIcon: const Icon(Icons.devices_rounded, color: Color(0xFF10B981)),
          suffixIcon: _nameController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  onPressed: () {
                    _nameController.clear();
                    setState(() {});
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: emojis.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          final emoji = emojis[index];
          final isSelected = _selectedEmoji == emoji;

          return InkWell(
            onTap: () {
              setState(() => _selectedEmoji = emoji);
              HapticFeedback.selectionClick();
            },
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF10B981).withValues(alpha: 0.22)
                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF10B981)
                      : Colors.transparent,
                  width: 2.2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: isSelected ? 26 : 22,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNetworkInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline_rounded, color: Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How device identity works',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your chosen name & avatar emoji will be instantly seen by other NearMitra users on LAN radar, Direct Wi-Fi connections, and Internet mesh without exposing your private phone number or email.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                    height: 1.4,
                  ),
                ),
                if (_deviceId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Hardware Device ID: ${_deviceId.length > 16 ? '${_deviceId.substring(0, 16)}...' : _deviceId}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
