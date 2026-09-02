import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_item.dart';
import '../models/peer.dart';
import '../services/file_opener_service.dart';
import '../services/history_service.dart';
import '../services/nearby_service.dart';

class ActivityLogsScreen extends ConsumerStatefulWidget {
  const ActivityLogsScreen({
    super.key,
    required this.service,
    required this.historyService,
    this.onStartCall,
    this.onOpenChatWithPeer,
    this.initialTabIndex = 0,
  });

  final NearbyService service;
  final HistoryService historyService;
  final Function(Peer peer, bool isVideoCall)? onStartCall;
  final Function(Peer peer)? onOpenChatWithPeer;
  final int initialTabIndex;

  @override
  ConsumerState<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<ChatItem> _allHistory = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Call filter: 0: All, 1: Audio, 2: Video, 3: Missed
  int _callFilterIndex = 0;
  // File filter: 0: All, 1: Media, 2: Docs, 3: Archives/APKs
  int _fileFilterIndex = 0;

  final Set<String> _expandedCallIds = {};
  final Set<String> _expandedFileIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await widget.historyService.load();
    if (mounted) {
      setState(() {
        _allHistory = history;
        _isLoading = false;
      });
    }
  }

  List<ChatItem> get _callLogs {
    return _allHistory.where((item) {
      final text = item.text ?? '';
      final isCall = text.contains('Audio Call') ||
          text.contains('Video Call') ||
          text.contains('Missed Call') ||
          text.contains('Call •') ||
          text.contains('Call');
      if (!isCall) return false;

      if (_searchQuery.isNotEmpty) {
        final matchesSender = item.sender.toLowerCase().contains(_searchQuery);
        final matchesPeer = item.peerId.toLowerCase().contains(_searchQuery);
        final matchesText = text.toLowerCase().contains(_searchQuery);
        if (!matchesSender && !matchesPeer && !matchesText) return false;
      }

      if (_callFilterIndex == 1 && !text.contains('Audio Call')) return false;
      if (_callFilterIndex == 2 && !text.contains('Video Call')) return false;

      return true;
    }).toList().reversed.toList();
  }

  List<ChatItem> get _receivedFiles {
    return _allHistory.where((item) {
      final isReceivedFile = !item.mine &&
          (item.kind == ChatKind.file || item.kind == ChatKind.folder) &&
          item.filePath != null;
      if (!isReceivedFile) return false;

      final fileName = item.fileName ?? '';

      if (_searchQuery.isNotEmpty) {
        final matchesFile = fileName.toLowerCase().contains(_searchQuery);
        final matchesSender = item.sender.toLowerCase().contains(_searchQuery);
        if (!matchesFile && !matchesSender) return false;
      }

      if (_fileFilterIndex == 1) {
        final isMedia = RegExp(
                r'\.(jpg|jpeg|png|gif|webp|mp4|mkv|mov|mp3|wav|m4a|aac)$',
                caseSensitive: false)
            .hasMatch(fileName);
        if (!isMedia) return false;
      } else if (_fileFilterIndex == 2) {
        final isDoc = RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|csv|json)$',
                caseSensitive: false)
            .hasMatch(fileName);
        if (!isDoc) return false;
      } else if (_fileFilterIndex == 3) {
        final isArchive = RegExp(r'\.(zip|rar|7z|tar|gz|apk)$',
                caseSensitive: false)
            .hasMatch(fileName) || item.kind == ChatKind.folder;
        if (!isArchive) return false;
      }

      return true;
    }).toList().reversed.toList();
  }

  // Analytics Metrics
  int get _totalCallsCount => _allHistory.where((i) {
        final t = i.text ?? '';
        return t.contains('Audio Call') ||
            t.contains('Video Call') ||
            t.contains('Call');
      }).length;

  int get _missedCallsCount => _allHistory.where((i) {
        final t = (i.text ?? '').toLowerCase();
        return t.contains('missed') || t.contains('declined') || t.contains('no answer');
      }).length;

  int get _totalReceivedFilesCount => _allHistory
      .where((i) =>
          !i.mine &&
          (i.kind == ChatKind.file || i.kind == ChatKind.folder) &&
          i.filePath != null)
      .length;

  int get _totalBytesReceived {
    int sum = 0;
    for (final i in _allHistory) {
      if (!i.mine && i.filePath != null && i.fileSize != null) {
        sum += i.fileSize!;
      }
    }
    return sum;
  }

  String _formatTotalBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Peer _resolvePeerFromItem(ChatItem item) {
    for (final p in widget.service.peers) {
      if (p.id == item.peerId || p.ip == item.peerId) {
        return p;
      }
    }
    return Peer(
      id: item.peerId,
      name: item.sender,
      ip: item.peerId.contains('.') ? item.peerId : '',
      lastSeen: item.createdAt,
    );
  }

  Future<void> _openFile(String path) async {
    await FileOpenerService.openOrInstallFile(context, path);
  }

  Future<void> _clearLogs(bool forCalls) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(forCalls ? 'Clear Call Logs?' : 'Clear Received Files?',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text(
          forCalls
              ? 'Are you sure you want to clear all call history? This action cannot be undone.'
              : 'Are you sure you want to remove received file records from history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        if (forCalls) {
          _allHistory.removeWhere((i) {
            final t = i.text ?? '';
            return t.contains('Audio Call') ||
                t.contains('Video Call') ||
                t.contains('Missed Call') ||
                t.contains('Call');
          });
        } else {
          _allHistory.removeWhere((i) =>
              !i.mine &&
              (i.kind == ChatKind.file || i.kind == ChatKind.folder));
        }
      });
      await widget.historyService.save(_allHistory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090E17) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Activity & History Hub',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF0B1320) : Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Logs',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Top Analytics Hero Card
          _buildAnalyticsHeroCard(scheme, isDark),

          // 2. Custom Modern Floating Tab Switcher
          _buildFloatingTabBar(scheme, isDark),

          // 3. Search & Quick Filters Strip
          _buildSearchAndFiltersStrip(scheme, isDark),

          // 4. Tab Views
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCallsTab(scheme, isDark),
                      _buildReceivedFilesTab(scheme, isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsHeroCard(ColorScheme scheme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0F231D), const Color(0xFF0D1B2A)]
              : [const Color(0xFFE8F5E9), const Color(0xFFE0F2FE)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.08 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildHeroMetricItem(
            icon: Icons.call_rounded,
            color: const Color(0xFF10B981),
            label: 'Total Calls',
            value: '$_totalCallsCount',
            subLabel: '$_missedCallsCount missed',
            isDark: isDark,
          ),
          Container(
            height: 38,
            width: 1,
            color: (isDark ? Colors.white24 : Colors.black12),
          ),
          _buildHeroMetricItem(
            icon: Icons.folder_shared_rounded,
            color: const Color(0xFF3B82F6),
            label: 'Files Received',
            value: '$_totalReceivedFilesCount',
            subLabel: _formatTotalBytes(_totalBytesReceived),
            isDark: isDark,
          ),
          Container(
            height: 38,
            width: 1,
            color: (isDark ? Colors.white24 : Colors.black12),
          ),
          _buildHeroMetricItem(
            icon: Icons.bolt_rounded,
            color: const Color(0xFF8B5CF6),
            label: 'P2P Direct',
            value: '${widget.service.peers.length} Online',
            subLabel: 'High Speed',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetricItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String subLabel,
    required bool isDark,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        Text(
          subLabel,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingTabBar(ColorScheme scheme, bool isDark) {
    final isCallsActive = _tabController.index == 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141F32) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => setState(() => _tabController.animateTo(0)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isCallsActive
                      ? (isDark ? const Color(0xFF0F2E24) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: isCallsActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phone_in_talk_rounded,
                      size: 17,
                      color: isCallsActive
                          ? const Color(0xFF10B981)
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Calls (${_callLogs.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isCallsActive
                          ? (isDark ? Colors.white : const Color(0xFF10B981))
                          : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => setState(() => _tabController.animateTo(1)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !isCallsActive
                      ? (isDark ? const Color(0xFF0F2E24) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: !isCallsActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_shared_rounded,
                      size: 17,
                      color: !isCallsActive
                          ? const Color(0xFF10B981)
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Files (${_receivedFiles.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: !isCallsActive
                          ? (isDark ? Colors.white : const Color(0xFF10B981))
                          : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFiltersStrip(ColorScheme scheme, bool isDark) {
    final isCallsTab = _tabController.index == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // Search Box with Clean Glow
          TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: isCallsTab
                  ? 'Search caller name, duration or IP…'
                  : 'Search file name or sender…',
              hintStyle: const TextStyle(fontSize: 12.5),
              prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Color(0xFF10B981)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              filled: true,
              fillColor: isDark ? const Color(0xFF111C2E) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Filter Pills Row with Clear Button
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: isCallsTab
                  ? [
                      _modernFilterPill('All', 0, isCallsTab, Icons.apps_rounded, isDark),
                      const SizedBox(width: 6),
                      _modernFilterPill('Audio', 1, isCallsTab, Icons.phone_rounded, isDark),
                      const SizedBox(width: 6),
                      _modernFilterPill('Video', 2, isCallsTab, Icons.videocam_rounded, isDark),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.all(8),
                        ),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                        tooltip: 'Clear Call History',
                        onPressed: () => _clearLogs(true),
                      ),
                    ]
                  : [
                      _modernFilterPill('All', 0, isCallsTab, Icons.apps_rounded, isDark),
                      const SizedBox(width: 6),
                      _modernFilterPill('Media', 1, isCallsTab, Icons.photo_library_rounded, isDark),
                      const SizedBox(width: 6),
                      _modernFilterPill('Docs', 2, isCallsTab, Icons.description_rounded, isDark),
                      const SizedBox(width: 6),
                      _modernFilterPill('Archives', 3, isCallsTab, Icons.inventory_2_rounded, isDark),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.all(8),
                        ),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                        tooltip: 'Clear File History',
                        onPressed: () => _clearLogs(false),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernFilterPill(
      String label, int index, bool isCallsTab, IconData icon, bool isDark) {
    final selected = isCallsTab
        ? _callFilterIndex == index
        : _fileFilterIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          if (isCallsTab) {
            _callFilterIndex = index;
          } else {
            _fileFilterIndex = index;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.2)
              : (isDark ? const Color(0xFF141F32) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF10B981) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected
                    ? const Color(0xFF10B981)
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsTab(ColorScheme scheme, bool isDark) {
    final calls = _callLogs;

    if (calls.isEmpty) {
      return _buildEmptyState(
        icon: Icons.phone_missed_rounded,
        title: 'No Call Records Found',
        subtitle: _searchQuery.isNotEmpty
            ? 'No calls match your search query.'
            : 'Your incoming and outgoing audio & video call logs will appear here.',
        isDark: isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: calls.length,
      itemBuilder: (context, index) {
        final item = calls[index];
        final callId = '${item.peerId}_${item.createdAt.millisecondsSinceEpoch}';
        final isExpanded = _expandedCallIds.contains(callId);

        String displayName = item.sender.trim();
        if (displayName.isEmpty || displayName == 'Peer Device' || displayName == widget.service.deviceName) {
          try {
            final matched = widget.service.peers.firstWhere(
              (p) => p.id == item.peerId || p.ip == item.peerId,
              orElse: () => Peer(id: item.peerId, name: '', ip: ''),
            );
            if (matched.name.isNotEmpty) {
              displayName = matched.name;
            } else if (item.peerId.isNotEmpty && item.peerId != 'local_ai_assistant') {
              displayName = item.peerId;
            } else {
              displayName = 'Peer Device';
            }
          } catch (_) {
            displayName = item.peerId.isNotEmpty ? item.peerId : 'Peer Device';
          }
        }

        final text = item.text ?? '';
        final isVideo = text.contains('Video Call');
        final isMissed = text.toLowerCase().contains('missed') ||
            text.toLowerCase().contains('no answer') ||
            text.toLowerCase().contains('declined');
        final isOutgoing = item.mine;

        final durationStr = text.contains('•')
            ? text.split('•').last.trim()
            : (isMissed ? 'Missed' : 'Completed');

        final callColor = isMissed
            ? const Color(0xFFEF4444)
            : (isVideo ? const Color(0xFF3B82F6) : const Color(0xFF10B981));

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111C2E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded
                  ? callColor.withValues(alpha: 0.6)
                  : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCallIds.remove(callId);
                } else {
                  _expandedCallIds.add(callId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Avatar Badge with Call Direction
                      Stack(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  callColor.withValues(alpha: 0.25),
                                  callColor.withValues(alpha: 0.08),
                                ],
                              ),
                              border: Border.all(color: callColor.withValues(alpha: 0.4)),
                            ),
                            child: Center(
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: callColor,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF111C2E) : Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isOutgoing
                                    ? Icons.call_made_rounded
                                    : (isMissed
                                        ? Icons.call_missed_rounded
                                        : Icons.call_received_rounded),
                                size: 12,
                                color: callColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // Name, Timestamp, Duration
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  item.formattedTime,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white60 : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: callColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isVideo
                                            ? Icons.videocam_rounded
                                            : Icons.phone_rounded,
                                        size: 11,
                                        color: callColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isVideo ? 'Video' : 'Voice',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: callColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  durationStr,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isMissed
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isMissed
                                        ? Colors.redAccent
                                        : (isDark ? Colors.white70 : Colors.black54),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Expand Indicator
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.white54 : Colors.black38,
                      ),
                    ],
                  ),

                  // Expandable Detailed Panel
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                        'Date & Time',
                        '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year} at ${item.formattedTime}',
                        isDark),
                    _buildDetailRow('Peer ID / IP', item.peerId, isDark),
                    _buildDetailRow(
                        'Call Direction',
                        isOutgoing ? 'Outgoing Call' : 'Incoming Call',
                        isDark),
                    _buildDetailRow('Duration / Status', durationStr, isDark),
                    const SizedBox(height: 12),

                    // Quick Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final peer = _resolvePeerFromItem(item);
                              widget.onStartCall?.call(peer, false);
                            },
                            icon: const Icon(Icons.call_rounded, size: 14),
                            label: const Text('Voice Call',
                                style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final peer = _resolvePeerFromItem(item);
                              widget.onStartCall?.call(peer, true);
                            },
                            icon: const Icon(Icons.videocam_rounded, size: 14),
                            label: const Text('Video Call',
                                style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF3B82F6),
                              side: const BorderSide(color: Color(0xFF3B82F6)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final peer = _resolvePeerFromItem(item);
                              widget.onOpenChatWithPeer?.call(peer);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.chat_bubble_outline_rounded,
                                size: 14),
                            label: const Text('Chat',
                                style: TextStyle(fontSize: 11.5)),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceivedFilesTab(ColorScheme scheme, bool isDark) {
    final files = _receivedFiles;

    if (files.isEmpty) {
      return _buildEmptyState(
        icon: Icons.folder_off_rounded,
        title: 'No Received Files Found',
        subtitle: _searchQuery.isNotEmpty
            ? 'No received files match your search query.'
            : 'Files and folders received over P2P local transfer will appear here.',
        isDark: isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final fileId = '${item.fileName}_${item.createdAt.millisecondsSinceEpoch}';
        final isExpanded = _expandedFileIds.contains(fileId);

        final fileName = item.fileName ?? 'Unknown File';
        final filePath = item.filePath ?? '';
        final fileIcon = _getFileIcon(fileName, item.kind == ChatKind.folder);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111C2E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded
                  ? fileIcon.color.withValues(alpha: 0.6)
                  : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedFileIds.remove(fileId);
                } else {
                  _expandedFileIds.add(fileId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      // File Type Glowing Icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              fileIcon.color.withValues(alpha: 0.25),
                              fileIcon.color.withValues(alpha: 0.08),
                            ],
                          ),
                          border: Border.all(
                              color: fileIcon.color.withValues(alpha: 0.4)),
                        ),
                        child: Icon(fileIcon.icon,
                            color: fileIcon.color, size: 22),
                      ),
                      const SizedBox(width: 12),

                      // File name, size, sender
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  item.formattedTime,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white60 : Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: fileIcon.color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.formattedSize.isNotEmpty
                                        ? item.formattedSize
                                        : 'Folder',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: fileIcon.color,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'From ${item.sender}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Expand Indicator
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.white54 : Colors.black38,
                      ),
                    ],
                  ),

                  // Expandable Details Panel
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow('File Name', fileName, isDark),
                    _buildDetailRow('Saved Path', filePath, isDark),
                    _buildDetailRow(
                        'Size',
                        item.fileSize != null
                            ? '${item.formattedSize} (${item.fileSize} bytes)'
                            : 'N/A',
                        isDark),
                    _buildDetailRow('Received From', item.sender, isDark),
                    _buildDetailRow(
                        'Received On',
                        '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year} at ${item.formattedTime}',
                        isDark),
                    const SizedBox(height: 12),

                    // Quick Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final peer = _resolvePeerFromItem(item);
                              widget.onOpenChatWithPeer?.call(peer);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.chat_bubble_outline_rounded,
                                size: 14),
                            label: const Text('Sender Chat',
                                style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : Colors.black87,
                              side: BorderSide(
                                  color: isDark ? Colors.white24 : Colors.black12),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final isApk = FileOpenerService.isApkFile(fileName);
                              return FilledButton.icon(
                                onPressed: () => _openFile(filePath),
                                icon: Icon(
                                  isApk ? Icons.install_mobile_rounded : Icons.open_in_new_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  isApk ? 'Install APK' : 'Open File',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white54 : Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
                    const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.15 : 0.05),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, size: 36, color: const Color(0xFF10B981)),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _FileIconInfo _getFileIcon(String fileName, bool isFolder) {
    if (isFolder) {
      return const _FileIconInfo(Icons.folder_rounded, Color(0xFFF59E0B));
    }
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return const _FileIconInfo(Icons.picture_as_pdf_rounded, Color(0xFFEF4444));
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return const _FileIconInfo(Icons.image_rounded, Color(0xFF10B981));
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi')) {
      return const _FileIconInfo(Icons.videocam_rounded, Color(0xFF3B82F6));
    }
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac')) {
      return const _FileIconInfo(Icons.audio_file_rounded, Color(0xFF8B5CF6));
    }
    if (lower.endsWith('.apk')) {
      return const _FileIconInfo(Icons.android_rounded, Color(0xFF10B981));
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.tar')) {
      return const _FileIconInfo(Icons.inventory_2_rounded, Color(0xFFEC4899));
    }
    return const _FileIconInfo(Icons.insert_drive_file_rounded, Color(0xFF64748B));
  }
}

class _FileIconInfo {
  final IconData icon;
  final Color color;
  const _FileIconInfo(this.icon, this.color);
}
