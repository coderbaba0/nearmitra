import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wan_models.dart';
import '../services/wan_service.dart';

class WanPairDialog extends StatefulWidget {
  const WanPairDialog({super.key});

  @override
  State<WanPairDialog> createState() => _WanPairDialogState();
}

class _WanPairDialogState extends State<WanPairDialog> with SingleTickerProviderStateMixin {
  final WanService _wanService = WanService();
  final TextEditingController _codeController = TextEditingController();

  late TabController _tabController;
  bool _isGenerating = false;
  bool _isClaiming = false;
  String? _generatedCode;
  String? _errorMessage;
  int _secondsRemaining = 300;
  Timer? _countdownTimer;
  StreamSubscription? _pairSuccessSub;
  bool _hasDismissed = false;

  void _dismissWithSuccess(WanDevice device) {
    if (_hasDismissed || !mounted) return;
    _hasDismissed = true;
    Navigator.of(context).pop(device);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully paired with ${device.name}!'),
        backgroundColor: const Color(0xFF005C4B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Auto generate code on open if on Tab 0
    _handleGenerateCode();

    // Auto-dismiss dialog immediately when either side pairs successfully
    _pairSuccessSub = _wanService.onPairSuccess.listen((device) {
      _dismissWithSuccess(device);
    });
  }

  @override
  void dispose() {
    _pairSuccessSub?.cancel();
    _tabController.dispose();
    _codeController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleGenerateCode() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final code = await _wanService.generatePairCode();
      if (!mounted) return;
      setState(() {
        _generatedCode = code;
        _isGenerating = false;
        _secondsRemaining = 300;
      });

      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_secondsRemaining > 0) {
          setState(() {
            _secondsRemaining--;
          });
        } else {
          timer.cancel();
          setState(() {
            _generatedCode = null;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleClaimCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Please enter a valid 6-digit code';
      });
      return;
    }

    setState(() {
      _isClaiming = true;
      _errorMessage = null;
    });

    try {
      final pairedDevice = await _wanService.claimPairCode(code);
      _dismissWithSuccess(pairedDevice);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isClaiming = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Farmitra / WhatsApp Palette
    final cardBg = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final innerBg = isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5);
    final borderColor = isDark ? const Color(0xFF2A3942) : const Color(0xFFE2E8F0);
    const primaryGreen = Color(0xFF005C4B);
    const accentGreen = Color(0xFF10B981);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: cardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentGreen.withValues(alpha: 0.15),
                  ),
                  child: const Icon(Icons.qr_code_2_rounded, color: accentGreen, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pair Internet Device',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Temporary 6-digit P2P handshake',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white60 : Colors.black54),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Segmented Tab Bar (My Code vs Enter Code)
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: innerBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: isDark ? primaryGreen : const Color(0xFF075E54),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
                labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Show Code'),
                  Tab(text: 'Enter Code'),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Error message container if present
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),

            // Tab View Body
            SizedBox(
              height: 175,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Show Generated Code
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isGenerating) ...[
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: accentGreen),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Generating Secure Code…',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ] else if (_generatedCode != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _generatedCode!,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                  color: accentGreen,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18, color: accentGreen),
                                tooltip: 'Copy Code',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _generatedCode!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Pair code copied!'),
                                      duration: Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enter this on Windows PC or peer phone',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Expires in ${_secondsRemaining ~/ 60}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                          ),
                        ] else ...[
                          Text(
                            'Code expired',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _handleGenerateCode,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('New Code'),
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryGreen,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Tab 2: Enter Peer Code
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                            fontFamily: 'monospace',
                            color: accentGreen,
                          ),
                          decoration: InputDecoration(
                            hintText: '000000',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white24 : Colors.black26,
                              letterSpacing: 6,
                            ),
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: accentGreen, width: 1.5),
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isClaiming ? null : _handleClaimCode,
                            style: FilledButton.styleFrom(
                              backgroundColor: isDark ? primaryGreen : const Color(0xFF075E54),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _isClaiming
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Pair & Save Peer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
