import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/p2p_peer.dart';


class WifiDirectService extends ChangeNotifier {
  static final WifiDirectService _instance = WifiDirectService._internal();
  factory WifiDirectService() => _instance;
  WifiDirectService._internal();

  static const MethodChannel _methodChannel = MethodChannel('farmitra_nearby/wifi_p2p');
  static const EventChannel _eventChannel = EventChannel('farmitra_nearby/wifi_p2p_events');

  StreamSubscription? _eventSubscription;
  bool _initialized = false;

  bool _isP2pEnabled = false;
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isGroupOwner = false;
  String? _groupOwnerIp;
  String? _localP2pIp;
  String? _thisDeviceAddress;
  String? _targetConnectingAddress;

  final List<P2pPeer> _peers = [];
  Function(String peerIp, String? localIp)? onP2pConnected;

  bool get isP2pEnabled => _isP2pEnabled;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isGroupOwner => _isGroupOwner;
  String? get groupOwnerIp => _groupOwnerIp;
  String? get localP2pIp => _localP2pIp;
  String? get thisDeviceAddress => _thisDeviceAddress;
  List<P2pPeer> get peers => List.unmodifiable(_peers);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _methodChannel.invokeMethod('initP2p');
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (err) {
          dev.log('[P2P DEBUG] EventChannel error: $err');
        },
      );
      dev.log('[P2P DEBUG] WifiDirectService initialized');
      await discoverPeers();
    } catch (e) {
      dev.log('[P2P DEBUG] WifiDirectService init error: $e');
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['event']?.toString();

    switch (type) {
      case 'state_changed':
        _isP2pEnabled = event['enabled'] == true;
        dev.log('[P2P DEBUG] P2P enabled: $_isP2pEnabled');
        notifyListeners();
        break;

      case 'peers_changed':
        final rawList = event['peers'] as List<dynamic>? ?? [];
        _peers.clear();
        for (final item in rawList) {
          if (item is Map) {
            final p = P2pPeer.fromMap(item);
            if (_targetConnectingAddress == p.deviceAddress && _targetConnectingAddress != null) {
              if (p.status == 3) p.status = 1; // Keep connecting status while forming
            }
            _peers.add(p);
            dev.log('[P2P DEBUG] peer found: ${p.name} (${p.deviceAddress}), status: ${p.statusLabel}');
          }
        }
        notifyListeners();
        break;

      case 'connection_changed':
        final connected = event['connected'] == true;
        _isConnected = connected;
        if (connected) {
          _isGroupOwner = event['isGroupOwner'] == true;
          _groupOwnerIp = event['groupOwnerIp']?.toString();
          _localP2pIp = event['localIp']?.toString();
          _targetConnectingAddress = null;

          dev.log('[P2P DEBUG] connected: true, GO: $_isGroupOwner, GO IP: $_groupOwnerIp, Local IP: $_localP2pIp');

          final peerIp = _isGroupOwner
              ? (_localP2pIp != null && _localP2pIp!.startsWith('192.168.49.')
                  ? '192.168.49.2'
                  : '192.168.49.1')
              : (_groupOwnerIp != null && _groupOwnerIp!.isNotEmpty
                  ? _groupOwnerIp!
                  : '192.168.49.1');

          onP2pConnected?.call(peerIp, _localP2pIp);
        } else {
          _isGroupOwner = false;
          _groupOwnerIp = null;
          _localP2pIp = null;
          dev.log('[P2P DEBUG] disconnected');
        }
        notifyListeners();
        break;

      case 'this_device_changed':
        _thisDeviceAddress = event['address']?.toString();
        dev.log('[P2P DEBUG] this device changed: ${event['name']} (${event['address']})');
        notifyListeners();
        break;
    }
  }

  Timer? _autoScanTimer;

  void startAutoDiscovery() {
    _autoScanTimer?.cancel();
    _isScanning = true;
    notifyListeners();
    _silentDiscover();
    _autoScanTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_isConnected) {
        _silentDiscover();
      }
    });
  }

  void stopAutoDiscovery() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _silentDiscover() async {
    try {
      await _methodChannel.invokeMethod<bool>('discoverPeers');
    } catch (e) {
      dev.log('[P2P DEBUG] silent discover error: $e');
    }
  }

  Future<bool> discoverPeers() async {
    try {
      _isScanning = true;
      dev.log('[P2P DEBUG] discovery requested');
      final ok = await _methodChannel.invokeMethod<bool>('discoverPeers') ?? false;
      return ok;
    } catch (e) {
      dev.log('[P2P DEBUG] discoverPeers error: $e');
      return false;
    }
  }

  Future<bool> connectP2pByAddress(String deviceAddress) async {
    if (deviceAddress.isEmpty) return false;
    try {
      _targetConnectingAddress = deviceAddress;
      notifyListeners();
      dev.log('[P2P DEBUG] connectP2pByAddress requested to $deviceAddress');
      final ok = await _methodChannel.invokeMethod<bool>('connectP2p', {
        'deviceAddress': deviceAddress,
      }) ?? false;
      if (!ok) {
        _targetConnectingAddress = null;
        notifyListeners();
      }
      return ok;
    } catch (e) {
      _targetConnectingAddress = null;
      notifyListeners();
      dev.log('[P2P DEBUG] connectP2pByAddress error: $e');
      return false;
    }
  }

  Future<bool> connectP2p(P2pPeer peer) async {
    try {
      _targetConnectingAddress = peer.deviceAddress;
      peer.status = 1; // Connecting
      notifyListeners();
      dev.log('[P2P DEBUG] connection requested to ${peer.name} (${peer.deviceAddress})');
      final ok = await _methodChannel.invokeMethod<bool>('connectP2p', {
        'deviceAddress': peer.deviceAddress,
      }) ?? false;
      if (!ok) {
        peer.status = 2; // Failed
        _targetConnectingAddress = null;
        notifyListeners();
        dev.log('[P2P DEBUG] connection failed for ${peer.name}');
      }
      return ok;
    } catch (e) {
      peer.status = 2;
      _targetConnectingAddress = null;
      notifyListeners();
      dev.log('[P2P DEBUG] connectP2p error: $e');
      return false;
    }
  }

  Future<void> openWifiSettings() async {
    try {
      await _methodChannel.invokeMethod('openWifiSettings');
    } catch (_) {}
  }

  Future<void> openLocationSettings() async {
    try {
      await _methodChannel.invokeMethod('openLocationSettings');
    } catch (_) {}
  }

  Future<bool> openFolder(String path) async {
    try {
      final ok = await _methodChannel.invokeMethod<bool>('openFolder', {'path': path}) ?? false;
      return ok;
    } catch (_) {
      return false;
    }
  }


  bool _isLocationEnabled = true;
  bool get isLocationEnabled => _isLocationEnabled;

  Future<bool> checkNativeWifiEnabled() async {
    try {
      final isEnabled = await _methodChannel.invokeMethod<bool>('isWifiEnabled') ?? false;
      if (_isP2pEnabled != isEnabled) {
        _isP2pEnabled = isEnabled;
        notifyListeners();
      }
      return isEnabled;
    } catch (_) {
      return _isP2pEnabled;
    }
  }

  Future<bool> checkNativeLocationEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      final isEnabled = await _methodChannel.invokeMethod<bool>('isLocationEnabled') ?? true;
      if (_isLocationEnabled != isEnabled) {
        _isLocationEnabled = isEnabled;
        notifyListeners();
      }
      return isEnabled;
    } catch (_) {
      return _isLocationEnabled;
    }
  }

  Future<bool> ensureP2pPermissionsAndWifi() async {
    if (!Platform.isAndroid) return true;

    try {
      final List<Permission> toRequest = [];
      final nearby = await Permission.nearbyWifiDevices.status;
      if (!nearby.isGranted) {
        toRequest.add(Permission.nearbyWifiDevices);
      }

      final loc = await Permission.location.status;
      if (!loc.isGranted) {
        toRequest.add(Permission.location);
      }

      if (toRequest.isNotEmpty) {
        await toRequest.request();
      }

      await checkNativeWifiEnabled();
      await checkNativeLocationEnabled();
    } catch (e) {
      dev.log('[P2P DEBUG] Permission check error: $e');
    }
    return _isP2pEnabled && _isLocationEnabled;
  }



  Future<bool> disconnectP2p() async {
    try {
      dev.log('[P2P DEBUG] disconnect requested');
      final ok = await _methodChannel.invokeMethod<bool>('disconnectP2p') ?? false;
      _isConnected = false;
      _targetConnectingAddress = null;
      notifyListeners();
      return ok;
    } catch (e) {
      dev.log('[P2P DEBUG] disconnectP2p error: $e');
      return false;
    }
  }


  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
