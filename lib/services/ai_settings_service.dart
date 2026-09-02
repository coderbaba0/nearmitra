import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiConfig {
  final String provider; // 'gemini', 'openai'
  final String geminiApiKey;
  final String geminiModel;
  final String openaiApiKey;
  final String openaiModel;
  final double temperature;
  final String systemPrompt;
  final bool isEnabled;

  const AiConfig({
    this.provider = 'gemini',
    this.geminiApiKey = '',
    this.geminiModel = 'gemini-2.0-flash',
    this.openaiApiKey = '',
    this.openaiModel = 'gpt-4o-mini',
    this.temperature = 0.7,
    this.systemPrompt =
        'You are NearMitra AI, a helpful, intelligent assistant for local off-grid communication.',
    this.isEnabled = true,
  });

  AiConfig copyWith({
    String? provider,
    String? geminiApiKey,
    String? geminiModel,
    String? openaiApiKey,
    String? openaiModel,
    double? temperature,
    String? systemPrompt,
    bool? isEnabled,
  }) {
    return AiConfig(
      provider: provider ?? this.provider,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      geminiModel: geminiModel ?? this.geminiModel,
      openaiApiKey: openaiApiKey ?? this.openaiApiKey,
      openaiModel: openaiModel ?? this.openaiModel,
      temperature: temperature ?? this.temperature,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class AiSettingsService extends ChangeNotifier {
  static final AiSettingsService _instance = AiSettingsService._internal();
  factory AiSettingsService() => _instance;
  AiSettingsService._internal();

  AiConfig _config = const AiConfig();
  AiConfig get config => _config;

  final Set<String> _allowedPeerIds = {};
  Set<String> get allowedPeerIds => Set.unmodifiable(_allowedPeerIds);

  final Set<String> _revokedPeerIds = {};
  Set<String> get revokedPeerIds => Set.unmodifiable(_revokedPeerIds);

  final Map<String, int> _peerRequestCounts = {};
  int _totalAiRequests = 0;
  int get totalAiRequests => _totalAiRequests;

  int getPeerRequestCount(String peerId) => _peerRequestCounts[peerId] ?? 0;

  void recordAiUsage(String peerId) {
    _totalAiRequests++;
    _peerRequestCounts[peerId] = (_peerRequestCounts[peerId] ?? 0) + 1;
    notifyListeners();
  }

  bool get hasConfiguredKey {
    if (_config.provider == 'openai') {
      return _config.openaiApiKey.trim().isNotEmpty;
    }
    return _config.geminiApiKey.trim().isNotEmpty;
  }

  bool isPeerAllowed(String peerId, [String peerIp = '']) {
    if (_revokedPeerIds.contains(peerId) ||
        (peerIp.isNotEmpty && _revokedPeerIds.contains(peerIp))) {
      return false;
    }
    return _allowedPeerIds.contains(peerId) ||
        (peerIp.isNotEmpty && _allowedPeerIds.contains(peerIp)) ||
        _allowedPeerIds.contains('*');
  }

  Future<void> setPeerAllowed(String peerId, bool allowed) async {
    if (allowed) {
      _allowedPeerIds.add(peerId);
      _revokedPeerIds.remove(peerId);
    } else {
      _allowedPeerIds.remove(peerId);
      _revokedPeerIds.add(peerId);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('ai_allowed_peers', _allowedPeerIds.toList());
      await prefs.setStringList('ai_revoked_peers', _revokedPeerIds.toList());
    } catch (_) {}
  }

  Future<void> allowAllPeers(Iterable<String> peerIds) async {
    _allowedPeerIds.addAll(peerIds);
    _revokedPeerIds.removeAll(peerIds);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('ai_allowed_peers', _allowedPeerIds.toList());
      await prefs.setStringList('ai_revoked_peers', _revokedPeerIds.toList());
    } catch (_) {}
  }

  Future<void> revokeAllPeers([Iterable<String>? peerIds]) async {
    if (peerIds != null) {
      _revokedPeerIds.addAll(peerIds);
      _allowedPeerIds.removeAll(peerIds);
    } else {
      _revokedPeerIds.addAll(_allowedPeerIds);
      _allowedPeerIds.clear();
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('ai_allowed_peers', _allowedPeerIds.toList());
      await prefs.setStringList('ai_revoked_peers', _revokedPeerIds.toList());
    } catch (_) {}
  }

  Future<String> generateAiResponse(String prompt, [String? senderId]) async {
    if (senderId != null && senderId.isNotEmpty) {
      recordAiUsage(senderId);
    } else {
      _totalAiRequests++;
      notifyListeners();
    }
    if (!_config.isEnabled) {
      return 'Nearby AI is currently disabled in AI Settings.';
    }
    if (_config.provider == 'openai') {
      return _queryOpenAI(prompt);
    } else {
      return _queryGemini(prompt);
    }
  }

  static const _kProvider = 'ai_provider';
  static const _kGeminiKey = 'ai_gemini_key';
  static const _kGeminiModel = 'ai_gemini_model';
  static const _kOpenaiKey = 'ai_openai_key';
  static const _kOpenaiModel = 'ai_openai_model';
  static const _kTemp = 'ai_temperature';
  static const _kSystemPrompt = 'ai_system_prompt';
  static const _kIsEnabled = 'ai_is_enabled';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var provider = prefs.getString(_kProvider) ?? 'gemini';
      if (provider == 'gemma') provider = 'gemini';

      var gModel = prefs.getString(_kGeminiModel) ?? 'gemini-2.0-flash';
      if (gModel.contains('1.0') || gModel == 'gemini-pro' || gModel.isEmpty) {
        gModel = 'gemini-2.0-flash';
      }

      final savedPeers = prefs.getStringList('ai_allowed_peers') ?? [];
      final savedRevoked = prefs.getStringList('ai_revoked_peers') ?? [];
      _allowedPeerIds.clear();
      _allowedPeerIds.addAll(savedPeers);
      _revokedPeerIds.clear();
      _revokedPeerIds.addAll(savedRevoked);

      _config = AiConfig(
        provider: provider,
        geminiApiKey: prefs.getString(_kGeminiKey) ?? '',
        geminiModel: gModel,
        openaiApiKey: prefs.getString(_kOpenaiKey) ?? '',
        openaiModel: prefs.getString(_kOpenaiModel) ?? 'gpt-4o-mini',
        temperature: prefs.getDouble(_kTemp) ?? 0.7,
        systemPrompt: prefs.getString(_kSystemPrompt) ??
            'You are NearMitra AI, a helpful, intelligent assistant for local off-grid communication.',
        isEnabled: prefs.getBool(_kIsEnabled) ?? true,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading AI settings: $e');
    }
  }

  Future<void> save(AiConfig newConfig) async {
    _config = newConfig;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProvider, newConfig.provider);
      await prefs.setString(_kGeminiKey, newConfig.geminiApiKey);
      await prefs.setString(_kGeminiModel, newConfig.geminiModel);
      await prefs.setString(_kOpenaiKey, newConfig.openaiApiKey);
      await prefs.setString(_kOpenaiModel, newConfig.openaiModel);
      await prefs.setDouble(_kTemp, newConfig.temperature);
      await prefs.setString(_kSystemPrompt, newConfig.systemPrompt);
      await prefs.setBool(_kIsEnabled, newConfig.isEnabled);
    } catch (e) {
      debugPrint('Error saving AI settings: $e');
    }
  }

  Future<List<String>> fetchGeminiModels(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return [];
    try {
      final client = HttpClient();
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$key');
      final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final list = data['models'] as List?;
        if (list != null && list.isNotEmpty) {
          final result = <String>[];
          for (final item in list) {
            if (item is Map) {
              final name = item['name']?.toString() ?? '';
              final methods = item['supportedGenerationMethods'] as List?;
              if (methods != null && methods.contains('generateContent')) {
                final clean = name.replaceFirst('models/', '');
                if (!clean.contains('embedding') &&
                    !clean.contains('aqa') &&
                    !clean.contains('imagen') &&
                    !clean.contains('1.0')) {
                  result.add(clean);
                }
              }
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (e) {
      debugPrint('Error fetching Gemini models: $e');
    }
    return [
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-pro',
    ];
  }

  Future<List<String>> fetchOpenAiModels(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return [];
    try {
      final client = HttpClient();
      final url = Uri.parse('https://api.openai.com/v1/models');
      final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
      req.headers.set('Authorization', 'Bearer $key');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final list = data['data'] as List?;
        if (list != null && list.isNotEmpty) {
          final result = <String>[];
          for (final item in list) {
            if (item is Map) {
              final id = item['id']?.toString() ?? '';
              if (id.startsWith('gpt-') ||
                  id.startsWith('o1') ||
                  id.startsWith('o3')) {
                result.add(id);
              }
            }
          }
          result.sort();
          if (result.isNotEmpty) return result;
        }
      }
    } catch (e) {
      debugPrint('Error fetching OpenAI models: $e');
    }
    return ['gpt-4o-mini', 'gpt-4o', 'o3-mini', 'gpt-4-turbo', 'gpt-3.5-turbo'];
  }

  Future<String> queryAi(String prompt) async {
    if (!_config.isEnabled) {
      return 'Nearby AI is currently disabled in settings.';
    }

    if (_config.provider == 'gemini') {
      return _queryGemini(prompt);
    } else if (_config.provider == 'openai') {
      return _queryOpenAI(prompt);
    }
    return _queryGemini(prompt);
  }

  Future<String> _queryGemini(String prompt, [String? overrideModel]) async {
    final key = _config.geminiApiKey.trim();
    if (key.isEmpty) {
      return 'Please configure Google Gemini API Key in AI Settings.';
    }

    var model = overrideModel ?? _config.geminiModel.trim();
    if (model.startsWith('models/')) {
      model = model.replaceFirst('models/', '');
    }
    if (model.contains('1.0') || model == 'gemini-pro' || model.isEmpty) {
      model = 'gemini-2.0-flash';
    }

    try {
      final client = HttpClient();
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key');

      final request =
          await client.postUrl(url).timeout(const Duration(seconds: 20));
      request.headers.set('Content-Type', 'application/json');

      final body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': '${_config.systemPrompt}\n\n$prompt'}
            ]
          }
        ],
        'generationConfig': {
          'temperature': _config.temperature,
        }
      });

      request.write(body);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text']?.toString().trim() ?? '';
          }
        }
        return 'No response text from Gemini.';
      } else {
        try {
          final err = jsonDecode(responseBody);
          final msg =
              err['error']?['message']?.toString() ?? response.reasonPhrase;
          // Auto-fallback if the specified model is deprecated/unsupported
          if ((msg.contains('not found') ||
                  msg.contains('no longer available') ||
                  msg.contains('models/') ||
                  response.statusCode == 404) &&
              overrideModel == null) {
            final fallbackModel = model == 'gemini-2.0-flash'
                ? 'gemini-1.5-flash'
                : 'gemini-2.0-flash';
            return _queryGemini(prompt, fallbackModel);
          }
          return 'Gemini Error ($model): $msg';
        } catch (_) {
          return 'Gemini Error (${response.statusCode}): $responseBody';
        }
      }
    } on SocketException catch (e) {
      return 'Gemini Network Error: Host lookup failed (${e.message}). Please check internet connection.';
    } catch (e) {
      return 'Gemini API error: $e';
    }
  }

  Future<String> _queryOpenAI(String prompt) async {
    if (_config.openaiApiKey.trim().isEmpty) {
      return 'Please configure OpenAI API Key in AI Settings for ChatGPT.';
    }
    try {
      final client = HttpClient();
      final model =
          _config.openaiModel.isNotEmpty ? _config.openaiModel.trim() : 'gpt-4o-mini';
      final url = Uri.parse('https://api.openai.com/v1/chat/completions');

      final request =
          await client.postUrl(url).timeout(const Duration(seconds: 20));
      request.headers
          .set('Authorization', 'Bearer ${_config.openaiApiKey.trim()}');
      request.headers.set('Content-Type', 'application/json');

      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': _config.systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': _config.temperature,
      });

      request.write(body);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final choices = decoded['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']?['content']?.toString();
          if (content != null) return content.trim();
        }
        return 'No response from ChatGPT.';
      } else {
        try {
          final err = jsonDecode(responseBody);
          return 'ChatGPT Error: ${err['error']?['message'] ?? response.reasonPhrase}';
        } catch (_) {
          return 'ChatGPT Error (${response.statusCode}): $responseBody';
        }
      }
    } on SocketException catch (e) {
      return 'ChatGPT Network Error: Host lookup failed (${e.message}). Please check internet connection.';
    } catch (e) {
      return 'OpenAI API error: $e';
    }
  }
}
