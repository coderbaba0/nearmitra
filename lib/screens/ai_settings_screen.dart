import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_settings_service.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final AiSettingsService _service = AiSettingsService();

  late String _provider;
  late TextEditingController _geminiKeyController;
  late TextEditingController _geminiModelController;
  late TextEditingController _openaiKeyController;
  late TextEditingController _openaiModelController;
  late TextEditingController _systemPromptController;
  late double _temperature;
  late bool _isEnabled;

  bool _isTesting = false;
  bool _isFetchingModels = false;
  String? _testResult;
  bool _testSuccess = false;

  List<String> _geminiModels = [
    'gemini-3.8-flash',
    'gemini-3.8-pro',
    'gemini-3.5-flash',
    'gemini-3.5-pro',
    'gemini-3.5-flash-thinking',
  ];

  List<String> _openaiModels = [
    'gpt-4o-mini',
    'gpt-4o',
    'o3-mini',
    'gpt-4-turbo',
    'gpt-3.5-turbo',
  ];

  @override
  void initState() {
    super.initState();
    final c = _service.config;
    var gModel = c.geminiModel.trim();
    if (gModel.contains('1.0') || gModel == 'gemini-pro' || gModel.isEmpty) {
      gModel = 'gemini-3.8-flash';
    }

    _provider = c.provider;
    _geminiKeyController = TextEditingController(text: c.geminiApiKey);
    _geminiModelController = TextEditingController(text: gModel);
    _openaiKeyController = TextEditingController(text: c.openaiApiKey);
    _openaiModelController = TextEditingController(text: c.openaiModel);
    _systemPromptController = TextEditingController(text: c.systemPrompt);
    _temperature = c.temperature;
    _isEnabled = c.isEnabled;
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _geminiModelController.dispose();
    _openaiKeyController.dispose();
    _openaiModelController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveModels() async {
    setState(() => _isFetchingModels = true);
    if (_provider == 'gemini') {
      final key = _geminiKeyController.text.trim();
      if (key.isEmpty) {
        _toast('Please enter your Gemini API Key first');
        setState(() => _isFetchingModels = false);
        return;
      }
      final list = await _service.fetchGeminiModels(key);
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
          _geminiModels = list;
          if (list.isNotEmpty && !_geminiModels.contains(_geminiModelController.text)) {
            _geminiModelController.text = list.first;
          }
        });
        _toast('Found ${list.length} supported Gemini models!');
      }
    } else {
      final key = _openaiKeyController.text.trim();
      if (key.isEmpty) {
        _toast('Please enter your OpenAI API Key first');
        setState(() => _isFetchingModels = false);
        return;
      }
      final list = await _service.fetchOpenAiModels(key);
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
          _openaiModels = list;
          if (list.isNotEmpty && !_openaiModels.contains(_openaiModelController.text)) {
            _openaiModelController.text = list.first;
          }
        });
        _toast('Found ${list.length} supported OpenAI models!');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _save() async {
    var gModel = _geminiModelController.text.trim();
    if (gModel.startsWith('models/')) {
      gModel = gModel.replaceFirst('models/', '');
    }
    if (gModel.isEmpty) gModel = 'gemini-3.8-flash';

    final updated = _service.config.copyWith(
      provider: _provider,
      geminiApiKey: _geminiKeyController.text.trim(),
      geminiModel: gModel,
      openaiApiKey: _openaiKeyController.text.trim(),
      openaiModel: _openaiModelController.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : _openaiModelController.text.trim(),
      temperature: _temperature,
      systemPrompt: _systemPromptController.text.trim(),
      isEnabled: _isEnabled,
    );
    await _service.save(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Settings Saved Successfully!'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    var gModel = _geminiModelController.text.trim();
    if (gModel.startsWith('models/')) {
      gModel = gModel.replaceFirst('models/', '');
    }
    if (gModel.isEmpty) gModel = 'gemini-3.8-flash';

    final tempConfig = _service.config.copyWith(
      provider: _provider,
      geminiApiKey: _geminiKeyController.text.trim(),
      geminiModel: gModel,
      openaiApiKey: _openaiKeyController.text.trim(),
      openaiModel: _openaiModelController.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : _openaiModelController.text.trim(),
      temperature: _temperature,
      systemPrompt: _systemPromptController.text.trim(),
      isEnabled: true,
    );
    await _service.save(tempConfig);

    final res =
        await _service.queryAi('Say "Connection Successful" in 2 words.');

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = res;
        _testSuccess = !res.toLowerCase().contains('error') &&
            !res.toLowerCase().contains('please configure') &&
            !res.toLowerCase().contains('failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Nearby AI Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, color: Color(0xFF10B981)),
            label: const Text(
              'Save',
              style: TextStyle(
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          // AI Toggle Banner
          Container(
            decoration: BoxDecoration(
              color: _isEnabled
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _isEnabled
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : scheme.outlineVariant,
              ),
            ),
            child: SwitchListTile(
              secondary: Icon(
                Icons.auto_awesome_rounded,
                color: _isEnabled ? const Color(0xFF10B981) : scheme.outline,
                size: 28,
              ),
              title: const Text(
                'Enable Nearby AI Assistant',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Text(
                _isEnabled
                    ? 'AI assistant is active for all nearby chat interactions'
                    : 'AI assistant is disabled',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              value: _isEnabled,
              onChanged: (val) => setState(() => _isEnabled = val),
            ),
          ),
          const SizedBox(height: 20),

          // Provider Section Header
          const Text(
            'SELECT AI ENGINE',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.grey),
          ),
          const SizedBox(height: 10),

          // 2 Provider Selection Cards (Gemini vs OpenAI)
          Row(
            children: [
              Expanded(
                child: _providerCard(
                  id: 'gemini',
                  title: 'Google Gemini',
                  subtitle: 'Flash 3.8, 3.0 & Pro',
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _providerCard(
                  id: 'openai',
                  title: 'ChatGPT',
                  subtitle: 'OpenAI GPT-4o',
                  icon: Icons.psychology_rounded,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Dynamic Credentials Form with custom model name support
          if (_provider == 'gemini') ...[
            _buildSectionHeader('Google Gemini Configuration'),
            TextField(
              controller: _geminiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Gemini API Key',
                hintText: 'Enter AIzaSy... API key',
                prefixIcon:
                    const Icon(Icons.key_rounded, color: Color(0xFF3B82F6)),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _geminiModelController,
              decoration: InputDecoration(
                labelText: 'Gemini Model Name',
                hintText: 'e.g. gemini-3.8-flash, or type custom model',
                prefixIcon: const Icon(Icons.psychology_alt_rounded,
                    color: Color(0xFF3B82F6)),
                suffixIcon: IconButton(
                  icon: _isFetchingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded,
                          color: Color(0xFF3B82F6)),
                  tooltip: 'Fetch Supported Models from API',
                  onPressed: _fetchLiveModels,
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _geminiModels
                  .map((m) => ChoiceChip(
                        label: Text(m, style: const TextStyle(fontSize: 11.5)),
                        selected: _geminiModelController.text == m,
                        selectedColor:
                            const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        onSelected: (sel) {
                          if (sel) {
                            setState(() => _geminiModelController.text = m);
                          }
                        },
                      ))
                  .toList(),
            ),
          ] else if (_provider == 'openai') ...[
            _buildSectionHeader('OpenAI / ChatGPT Configuration'),
            TextField(
              controller: _openaiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'OpenAI API Key',
                hintText: 'Enter sk-... API key',
                prefixIcon:
                    const Icon(Icons.key_rounded, color: Color(0xFF10B981)),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _openaiModelController,
              decoration: InputDecoration(
                labelText: 'OpenAI Model Name',
                hintText: 'e.g. gpt-4o-mini, gpt-4o, o3-mini',
                prefixIcon: const Icon(Icons.memory_rounded,
                    color: Color(0xFF10B981)),
                suffixIcon: IconButton(
                  icon: _isFetchingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded,
                          color: Color(0xFF10B981)),
                  tooltip: 'Fetch Models from OpenAI',
                  onPressed: _fetchLiveModels,
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _openaiModels
                  .map((m) => ChoiceChip(
                        label: Text(m, style: const TextStyle(fontSize: 11.5)),
                        selected: _openaiModelController.text == m,
                        selectedColor:
                            const Color(0xFF10B981).withValues(alpha: 0.2),
                        onSelected: (sel) {
                          if (sel) {
                            setState(() => _openaiModelController.text = m);
                          }
                        },
                      ))
                  .toList(),
            ),
          ],

          const SizedBox(height: 16),

          // Test Connection Button & Result Box
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded),
              label:
                  Text(_isTesting ? 'Testing API Key…' : 'Test API Connection'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: scheme.primary),
              ),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _testSuccess
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _testSuccess
                      ? const Color(0xFF10B981)
                      : Colors.redAccent,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testSuccess
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: _testSuccess
                        ? const Color(0xFF10B981)
                        : Colors.redAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          _buildSectionHeader('Model Parameters & Personality'),

          // Temperature Slider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Creativity (Temperature)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(_temperature.toStringAsFixed(2),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary)),
                  ],
                ),
                Slider(
                  value: _temperature,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  activeColor: scheme.primary,
                  onChanged: (val) => setState(() => _temperature = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // System Prompt
          TextField(
            controller: _systemPromptController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'System Prompt / AI Persona',
              alignLabelWithHint: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 24),
          // Professional Footer Branding
          Divider(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.mail_outline_rounded,
                size: 13,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 5),
              Text(
                'For support or suggestions: theflutterfever@gmail.com',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Built with ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const Icon(
                Icons.favorite_rounded,
                size: 14,
                color: Color(0xFFEF4444),
              ),
              const Text(
                ' Flutter and Kotlin',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '© 2026 NearMitra Ecosystem • All Rights Reserved',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),
    );
  }

  Widget _providerCard({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _provider == id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _provider = id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor:
                  isSelected ? color : Colors.grey.withValues(alpha: 0.2),
              radius: 20,
              child: Icon(icon,
                  color: isSelected ? Colors.white : Colors.grey, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected
                    ? color
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}
