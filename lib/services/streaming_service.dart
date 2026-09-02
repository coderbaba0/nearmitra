import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/peer.dart';

enum StreamType { camera, audio, screen }

class StreamingService extends ChangeNotifier {
  static final StreamingService _instance = StreamingService._internal();
  factory StreamingService() => _instance;
  StreamingService._internal();

  static const String _kAllowCamera = 'stream_allow_camera';
  static const String _kAllowAudio = 'stream_allow_audio';
  static const String _kAllowScreen = 'stream_allow_screen';
  static const String _kTrustedDevices = 'stream_trusted_devices';

  bool _allowCamera = false;
  bool _allowAudio = false;
  bool _allowScreen = false;
  final Set<String> _trustedDevices = {};

  bool get allowCamera => _allowCamera;
  bool get allowAudio => _allowAudio;
  bool get allowScreen => _allowScreen;
  Set<String> get trustedDevices => Set.unmodifiable(_trustedDevices);

  HttpServer? _rangeHttpServer;
  final int _rangeServerPort = 43890;
  int get rangeServerPort => _rangeServerPort;

  Function(Peer peer, String streamType, Function(bool allow, bool alwaysTrust) response)?
      onIncomingStreamRequest;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _allowCamera = prefs.getBool(_kAllowCamera) ?? false;
      _allowAudio = prefs.getBool(_kAllowAudio) ?? false;
      _allowScreen = prefs.getBool(_kAllowScreen) ?? false;
      final list = prefs.getStringList(_kTrustedDevices) ?? [];
      _trustedDevices.addAll(list);
    } catch (_) {}

    await _startRangeServer();
  }

  Future<void> setPermission({
    bool? allowCamera,
    bool? allowAudio,
    bool? allowScreen,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (allowCamera != null) {
      _allowCamera = allowCamera;
      await prefs.setBool(_kAllowCamera, allowCamera);
    }
    if (allowAudio != null) {
      _allowAudio = allowAudio;
      await prefs.setBool(_kAllowAudio, allowAudio);
    }
    if (allowScreen != null) {
      _allowScreen = allowScreen;
      await prefs.setBool(_kAllowScreen, allowScreen);
    }
    notifyListeners();
  }

  Future<void> setAllowCamera(bool val) => setPermission(allowCamera: val);
  Future<void> setAllowAudio(bool val) => setPermission(allowAudio: val);
  Future<void> setAllowScreen(bool val) => setPermission(allowScreen: val);

  Future<void> addTrustedDevice(String peerId) async {
    _trustedDevices.add(peerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTrustedDevices, _trustedDevices.toList());
    notifyListeners();
  }

  Future<void> removeTrustedDevice(String peerId) async {
    _trustedDevices.remove(peerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTrustedDevices, _trustedDevices.toList());
    notifyListeners();
  }

  bool isTrusted(String peerId) {
    return _trustedDevices.contains(peerId);
  }

  // --- HTTP Range Streaming Server for Instant File Preview ---
  Future<void> _startRangeServer() async {
    try {
      await _rangeHttpServer?.close(force: true);
      _rangeHttpServer = null;
      _rangeHttpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _rangeServerPort,
        shared: true,
      );
      _rangeHttpServer!.listen(_handleRangeRequest);
      debugPrint('HTTP Range Stream Server running on port $_rangeServerPort');
    } catch (e) {
      debugPrint('Error starting Range Stream Server: $e');
    }
  }

  Future<void> _handleRangeRequest(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    if (filePath == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fileSize = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    if (rangeHeader == null) {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = fileSize;
      await file.openRead().pipe(request.response);
      return;
    }

    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await request.response.close();
      return;
    }

    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    final end = (endStr != null && endStr.isNotEmpty) ? int.parse(endStr) : fileSize - 1;

    if (start >= fileSize || end >= fileSize || start > end) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await request.response.close();
      return;
    }

    final length = end - start + 1;
    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileSize');
    request.response.contentLength = length;

    final stream = file.openRead(start, end + 1);
    await stream.pipe(request.response);
  }

  String getFileStreamUrl(String localIp, String absoluteFilePath) {
    return 'http://$localIp:$_rangeServerPort/stream?path=${Uri.encodeComponent(absoluteFilePath)}';
  }

  void disposeServer() {
    _rangeHttpServer?.close(force: true);
  }
}
