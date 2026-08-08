import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../main.dart';
import '../models/chat_item.dart';
import '../models/peer.dart';
import '../services/history_service.dart';
import '../services/nearby_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/peer_tile.dart';
import '../widgets/transfer_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service});

  final NearbyService service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ChatMode { people, ai }

class _HomeScreenState extends State<HomeScreen> {
  final _message = TextEditingController();
  final _scroll = ScrollController();
  final _historyService = HistoryService();
  final List<ChatItem> _history = [];
  String? _selectedPeerId;
  bool _showLogs = false;
  bool _scanning = false;
  ChatMode _chatMode = ChatMode.people;
  bool _aiThinking = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    _init();
  }

  Future<void> _init() async {
    _history.addAll(await _historyService.load());
    await widget.service.start();
    if (mounted) setState(() {});
    _scan(); // Automatic scan on launch
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    widget.service.stop();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    final incoming = widget.service.takeIncomingItems();
    if (incoming.isNotEmpty) {
      _history.addAll(incoming);
      _historyService.save(_history);
    }
    if (mounted) {
      setState(() {});
      _triggerScrollToBottom();
    }
  }

  void _selectPeer(Peer p) {
    setState(() {
      _selectedPeerId = p.id;
      _lastSelectedPeer = p;
      p.unreadCount = 0;
    });
    _triggerScrollToBottom();
  }

  void _triggerScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    });
  }

  Peer? _lastSelectedPeer;

  Peer? get _selectedPeer {
    if (_selectedPeerId == null) return null;
    for (final p in widget.service.peers) {
      if (p.id == _selectedPeerId || p.ip == _selectedPeerId) {
        _lastSelectedPeer = p;
        return p;
      }
    }
    return _lastSelectedPeer;
  }

  List<ChatItem> get _currentChat {
    final peer = _selectedPeer;
    if (peer == null) return [];
    return _history.where((e) {
      final isMatch = e.peerId == peer.id ||
             e.peerId == peer.ip ||
             (!e.mine && (e.sender == peer.name || e.sender.contains(peer.name) || peer.name.contains(e.sender)));
      if (!isMatch) return false;
      if (e.isAi && (e.text == null || e.text!.isEmpty)) return false;
      return _chatMode == ChatMode.ai ? e.isAi : !e.isAi;
    }).toList();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    await widget.service.announce();
    await widget.service.scanSubnet();
    if (mounted) setState(() => _scanning = false);
  }

  Timer? _typingDebounce;

  void _onTextChanged(String text) {
    final peer = _selectedPeer;
    if (peer == null) return;
    if (text.isNotEmpty) {
      widget.service.sendTypingStatus(peer, true);
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(milliseconds: 2200), () {
        widget.service.sendTypingStatus(peer, false);
      });
    } else {
      _typingDebounce?.cancel();
      widget.service.sendTypingStatus(peer, false);
    }
  }

  Future<void> _sendMessage() async {
    final peer = _selectedPeer;
    final text = _message.text.trim();
    if (peer == null || text.isEmpty) return;
    _message.clear();
    _typingDebounce?.cancel();
    widget.service.sendTypingStatus(peer, false);

    if (_chatMode == ChatMode.ai) {
      final userPromptItem = ChatItem(
        peerId: peer.id,
        sender: widget.service.deviceName,
        mine: true,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: text,
        isAi: true,
      );
      _history.add(userPromptItem);

      final aiResponseItem = ChatItem(
        peerId: peer.id,
        sender: '${peer.name} AI',
        mine: false,
        createdAt: DateTime.now(),
        kind: ChatKind.text,
        text: '',
        isAi: true,
      );
      _history.add(aiResponseItem);
      await _historyService.save(_history);

      setState(() {
        _aiThinking = true;
      });
      _triggerScrollToBottom();

      final typeQueue = <String>[];
      var isStreamFinished = false;
      Timer? typewriterTimer;

      void processTypeQueue() {
        if (!mounted) return;
        if (typeQueue.isEmpty) {
          if (isStreamFinished && typewriterTimer != null) {
            typewriterTimer?.cancel();
            typewriterTimer = null;
          }
          return;
        }

        // Adaptive batch size: fast, smooth character typing
        final batchSize = typeQueue.length > 100 ? 8 : (typeQueue.length > 40 ? 4 : 2);
        final toTake = batchSize < typeQueue.length ? batchSize : typeQueue.length;

        final chars = typeQueue.sublist(0, toTake).join();
        typeQueue.removeRange(0, toTake);

        aiResponseItem.text = (aiResponseItem.text ?? '') + chars;

        if (_aiThinking) {
          _aiThinking = false;
        }

        setState(() {});
        _scrollToBottomImmediate();
      }

      typewriterTimer = Timer.periodic(const Duration(milliseconds: 14), (_) {
        processTypeQueue();
      });

      await for (final chunk in widget.service.streamAiPrompt(peer, text)) {
        if (chunk.isNotEmpty) {
          typeQueue.addAll(chunk.split(''));
        }
      }

      isStreamFinished = true;

      // Drain remaining typing queue smoothly
      while (typeQueue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 15));
      }

      typewriterTimer?.cancel();
      typewriterTimer = null;

      if (aiResponseItem.text == null || aiResponseItem.text!.isEmpty) {
        final hasIncomingAi = _history.any((e) =>
            e != aiResponseItem &&
            (e.peerId == peer.id || e.peerId == peer.ip) &&
            e.isAi &&
            !e.mine &&
            e.text != null &&
            e.text!.isNotEmpty);
        if (hasIncomingAi) {
          _history.remove(aiResponseItem);
        } else {
          aiResponseItem.text = 'Nearby AI is not enabled on this device.';
        }
      }

      await _historyService.save(_history);

      if (mounted) {
        setState(() {
          _aiThinking = false;
        });
        _triggerScrollToBottom();
      }
      return;
    }

    final ok = await widget.service.sendChat(peer, text);
    if (!ok) return;
    _history.add(ChatItem(
      peerId: peer.id,
      sender: widget.service.deviceName,
      mine: true,
      createdAt: DateTime.now(),
      kind: ChatKind.text,
      text: text,
      isAi: false,
    ));
    await _historyService.save(_history);
    setState(() {});
    _triggerScrollToBottom();
  }

  Future<void> _pickAndSend() async {
    final peer = _selectedPeer;
    if (peer == null) {
      _toast('Select a nearby device first');
      return;
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: false);
    final path = result?.files.single.path;
    if (path == null) return;
    final file = File(path);
    final name = result!.files.single.name;
    final size = await file.length();
    final ok = await widget.service.sendFile(peer, file, displayName: name);
    if (!ok) return;
    _history.add(ChatItem(peerId: peer.id, sender: widget.service.deviceName, mine: true, createdAt: DateTime.now(), kind: ChatKind.file, fileName: name, filePath: path, fileSize: size, status: 'Sent'));
    await _historyService.save(_history);
    setState(() {});
    _triggerScrollToBottom();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      max,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToBottomImmediate() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(max);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final peer = _selectedPeer;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            if (!compact || peer == null) _topBar(),
            Expanded(
              child: compact
                  ? _mobileBody()
                  : Row(
                      children: [
                        SizedBox(width: 320, child: _devicePane()),
                        VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45)),
                        Expanded(child: _chatPane()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25))),
      ),
      child: Row(
        children: [
          // Compact Title on Left (No icon, No description to prevent overflow)
          const Text(
            'Farmitra',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: -0.3),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Online',
              style: TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const Spacer(),
          // Compact Right Action Icons (File History, Scan, Settings)
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            iconSize: 19,
            tooltip: 'Received Files',
            style: IconButton.styleFrom(backgroundColor: const Color(0xFF169B62).withValues(alpha: 0.12)),
            color: const Color(0xFF169B62),
            onPressed: _openReceivedFilesModal,
            icon: const Icon(Icons.folder_shared_rounded),
          ),
          const SizedBox(width: 6),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            iconSize: 19,
            tooltip: 'Scan network',
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
            onPressed: _scan,
            icon: AnimatedRotation(
              turns: _scanning ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 6),
          // Settings Icon (Replaces log icon)
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            iconSize: 19,
            tooltip: 'Settings',
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
            onPressed: _openSettingsModal,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettingsModal() async {
    final currentDir = await widget.service.getReceiveDirectory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF169B62).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.settings_rounded, color: Color(0xFF169B62)),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Settings',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  
                  // 1. App Theme Mode Switcher
                  const Text('App Theme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _themeOptionCard(
                          context,
                          title: 'System',
                          icon: Icons.brightness_auto_rounded,
                          mode: ThemeMode.system,
                          current: themeNotifier.value,
                          onTap: () {
                            themeNotifier.value = ThemeMode.system;
                            setModalState(() {});
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _themeOptionCard(
                          context,
                          title: 'Light',
                          icon: Icons.light_mode_rounded,
                          mode: ThemeMode.light,
                          current: themeNotifier.value,
                          onTap: () {
                            themeNotifier.value = ThemeMode.light;
                            setModalState(() {});
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _themeOptionCard(
                          context,
                          title: 'Dark',
                          icon: Icons.dark_mode_rounded,
                          mode: ThemeMode.dark,
                          current: themeNotifier.value,
                          onTap: () {
                            themeNotifier.value = ThemeMode.dark;
                            setModalState(() {});
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. Local Notifications Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: const Color(0xFF169B62),
                    title: const Text('Local Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                    subtitle: const Text('Show alerts when chat messages or files arrive', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    value: widget.service.notificationsEnabled,
                    onChanged: (val) {
                      setModalState(() {
                        widget.service.notificationsEnabled = val;
                      });
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),

                  // 3. Received File Save Location
                  const Text('Received File Storage Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_open_rounded, color: Color(0xFF169B62), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.service.customSavePath ?? currentDir.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            final selected = await FilePicker.platform.getDirectoryPath();
                            if (selected != null) {
                              setModalState(() {
                                widget.service.customSavePath = selected;
                              });
                              setState(() {});
                            }
                          },
                          child: const Text('Change', style: TextStyle(color: Color(0xFF169B62), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _themeOptionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode current,
    required VoidCallback onTap,
  }) {
    final selected = current == mode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF169B62).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF169B62) : Colors.grey.withValues(alpha: 0.3),
            width: selected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? const Color(0xFF169B62) : Colors.grey),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFF169B62) : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReceivedFilesModal() async {
    final dir = await widget.service.getReceiveDirectory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final receivedFiles = _history.where((e) => e.kind != ChatKind.text && !e.mine).toList();

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2C34) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF169B62).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.folder_shared_rounded, color: Color(0xFF169B62), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Received Files Location',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          dir.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF169B62),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: () {
                      OpenFilex.open(dir.path);
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Open Folder'),
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Text('File History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  Text('${receivedFiles.length} files', style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: receivedFiles.isEmpty
                    ? const Center(
                        child: Text(
                          'No received files yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: receivedFiles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                        itemBuilder: (context, index) {
                          final item = receivedFiles[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF169B62).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                item.kind == ChatKind.folder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                                color: const Color(0xFF169B62),
                              ),
                            ),
                            title: Text(
                              item.fileName ?? 'File',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              'From ${item.sender} • ${item.formattedTime}',
                              style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF169B62)),
                              onPressed: item.filePath == null ? null : () => OpenFilex.open(item.filePath!),
                              tooltip: 'Open File',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mobileBody() {
    if (_selectedPeer == null) return _devicePane();
    return Column(
      children: [
        _whatsappPeerHeader(_selectedPeer!),
        Expanded(child: _chatPane(isMobile: true)),
      ],
    );
  }

  Widget _whatsappPeerHeader(Peer peer) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : const Color(0xFF075E54),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => setState(() {
              _selectedPeerId = null;
              _lastSelectedPeer = null;
            }),
          ),
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white24,
                child: Text(
                  peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                peer.isTyping
                    ? const Text(
                        'typing…',
                        style: TextStyle(
                          color: Color(0xFF25D366),
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Text(
                        'Online • ${peer.ip}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.attach_file_rounded, color: Colors.white),
            tooltip: 'Send file',
            onPressed: _pickAndSend,
          ),
          IconButton(
            icon: Icon(_showLogs ? Icons.article_rounded : Icons.article_outlined, color: Colors.white),
            tooltip: 'Activity log',
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
        ],
      ),
    );
  }

  Widget _devicePane() {
    final peers = widget.service.peers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Nearby devices', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${peers.length} active',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_scanning && peers.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Scanning local network for devices…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: peers.isEmpty
                ? _RadarPulseScanner(
                    isScanning: _scanning,
                    onScanPressed: _scan,
                  )
                : ListView.separated(
                    itemCount: peers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final p = peers[index];
                      return PeerTile(
                        peer: p,
                        selected: p.id == _selectedPeerId,
                        onTap: () => _selectPeer(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chatPane({bool isMobile = false}) {
    final peer = _selectedPeer;
    if (peer == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Select a device to start chatting',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      );
    }
    final chat = _currentChat;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // WhatsApp-like chat background color
    final chatBg = isDark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2);

    return Container(
      color: chatBg,
      child: Column(
        children: [
          if (!isMobile) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark ? const Color(0xFF1F2C34) : Colors.white,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF169B62),
                    child: Text(
                      peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(peer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Online • ${peer.ip}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: _pickAndSend, tooltip: 'Send file', icon: const Icon(Icons.attach_file_rounded)),
                ],
              ),
            ),
          ],

          // People | Nearby AI Mode Switcher
          _buildChatModeSwitch(isDark, peer),

          Expanded(
            child: (chat.isEmpty && !_aiThinking)
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF182229) : const Color(0xFFFFF5C4),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Text(
                        _chatMode == ChatMode.ai
                            ? '🤖 Nearby AI Mode: Prompts are handled by ${peer.name}'
                            : '🔒 End-to-end local network chat with ${peer.name}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : const Color(0xFF54656F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    itemCount: chat.length + (_aiThinking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_aiThinking && index == chat.length) {
                        return _buildAiThinkingBubble(isDark, peer);
                      }
                      return ChatBubble(item: chat[index]);
                    },
                  ),
          ),
          if (_chatMode == ChatMode.people) TransferCard(state: widget.service.transfer),
          if (_showLogs) ...[
            Container(
              height: 120,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: isDark ? const Color(0xFF1F2C34) : Colors.black87,
              child: ListView(
                children: widget.service.logs.reversed.take(30).map((e) => Text(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.greenAccent))).toList(),
              ),
            ),
          ],
          // Floating Input Box
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF202C33) : Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        if (_chatMode == ChatMode.people) ...[
                          IconButton(
                            icon: Icon(Icons.attach_file_rounded, color: isDark ? Colors.grey[400] : const Color(0xFF54656F)),
                            onPressed: _pickAndSend,
                            tooltip: 'Attach file',
                          ),
                        ] else ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: TextField(
                            controller: _message,
                            textInputAction: TextInputAction.send,
                            onChanged: _onTextChanged,
                            onSubmitted: (_) => _sendMessage(),
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: _chatMode == ChatMode.ai ? 'Ask ${peer.name} Nearby AI…' : 'Message…',
                              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : const Color(0xFF8696A0)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _chatMode == ChatMode.ai ? const Color(0xFF10B981) : const Color(0xFF169B62),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_chatMode == ChatMode.ai ? const Color(0xFF10B981) : const Color(0xFF169B62)).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _chatMode == ChatMode.ai ? Icons.auto_awesome_rounded : Icons.send_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatModeSwitch(bool isDark, Peer peer) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeSegmentButton(
            title: 'People',
            icon: Icons.person_rounded,
            mode: ChatMode.people,
            isDark: isDark,
          ),
          _modeSegmentButton(
            title: 'Nearby AI',
            icon: Icons.auto_awesome_rounded,
            mode: ChatMode.ai,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _modeSegmentButton({
    required String title,
    required IconData icon,
    required ChatMode mode,
    required bool isDark,
  }) {
    final active = _chatMode == mode;
    return GestureDetector(
      onTap: () {
        if (_chatMode == mode) return;
        setState(() {
          _chatMode = mode;
        });
        _triggerScrollToBottom();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? (mode == ChatMode.ai ? const Color(0xFF10B981) : const Color(0xFF169B62))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiThinkingBubble(bool isDark, Peer peer) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Waiting for ${peer.name} Nearby AI…',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF10B981),
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPulseScanner extends StatefulWidget {
  const _RadarPulseScanner({required this.isScanning, required this.onScanPressed});

  final bool isScanning;
  final VoidCallback onScanPressed;

  @override
  State<_RadarPulseScanner> createState() => _RadarPulseScannerState();
}

class _RadarPulseScannerState extends State<_RadarPulseScanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.isScanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RadarPulseScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning != oldWidget.isScanning) {
      if (widget.isScanning) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _RadarPainter(_controller.value, isDark: isDark, isScanning: widget.isScanning),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          border: Border.all(color: const Color(0xFF10B981), width: 2),
                        ),
                        child: Transform.rotate(
                          angle: widget.isScanning ? _controller.value * 2 * 3.1415926535 : 0,
                          child: const Icon(Icons.radar_rounded, size: 30, color: Color(0xFF10B981)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isScanning ? 'Scanning local network…' : 'No devices found',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(
              'Ensure Farmitra Nearby is open on another device connected to the same Wi‑Fi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: widget.onScanPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.search_rounded),
              label: Text(
                widget.isScanning ? 'Scanning…' : 'Scan Network',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.progress, {required this.isDark, required this.isScanning});

  final double progress;
  final bool isDark;
  final bool isScanning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    if (!isScanning) return;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + (i * 0.333)) % 1.0;
      final radius = waveProgress * maxRadius;
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: opacity * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}
