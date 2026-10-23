import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Switches the reserved video sender without replacing the call's audio stream.
class CallVideoSession {
  CallVideoSession({
    required this.localStream,
    required this.replaceVideo,
    required this.openCamera,
    required this.openScreen,
    required this.signalVideo,
    required this.onChanged,
    required this.onError,
    this.onScreenStopped,
    required this.cameraEnabled,
  });

  final MediaStream localStream;
  final Future<void> Function(MediaStreamTrack?) replaceVideo;
  final Future<MediaStream> Function() openCamera;
  final Future<MediaStream> Function() openScreen;
  final Future<void> Function(bool) signalVideo;
  final void Function() onChanged;
  final void Function(Object) onError;
  final Future<void> Function()? onScreenStopped;
  bool cameraEnabled;
  bool busy = false;
  bool _closed = false;
  bool _screenEnded = false;
  MediaStream? _cameraCapture;
  MediaStream? _screen;

  bool get sharing => _screen != null;
  MediaStream get preview => _screen ?? localStream;
  MediaStreamTrack? get _camera => localStream.getVideoTracks().firstOrNull;

  Future<void> _release(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      track.onEnded = null;
      await track.stop();
    }
    await stream.dispose();
  }

  Future<void> _releaseScreen(MediaStream? stream) async {
    if (stream == null) return;
    try {
      await _release(stream);
    } finally {
      await onScreenStopped?.call();
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_closed) return;
    if (busy) {
      throw StateError('A camera or screen change is already in progress');
    }
    busy = true;
    onChanged();
    try {
      await action();
    } finally {
      busy = false;
      if (!_closed) {
        onChanged();
        if (_screenEnded && sharing) {
          _screenEnded = false;
          unawaited(setScreenSharing(false)
              .catchError((Object error) => onError(error)));
        }
      }
    }
  }

  Future<void> setCamera(bool enabled) => _change(() async {
        MediaStream? acquired;
        final previousCamera = _camera;
        final wasEnabled = previousCamera?.enabled;
        try {
          var camera = previousCamera;
          if (enabled && camera == null) {
            acquired = await openCamera();
            if (_closed) {
              await _release(acquired);
              return;
            }
            camera = acquired.getVideoTracks().firstOrNull;
            if (camera == null) throw StateError('No camera is available');
          }
          if (camera != null) camera.enabled = enabled;
          await replaceVideo(enabled ? camera : null);
          if (_closed) {
            await _release(acquired);
            return;
          }
          if (acquired != null) {
            await localStream.addTrack(camera!);
            _cameraCapture = acquired;
          }
          final previous = _screen;
          _screen = null;
          cameraEnabled = enabled;
          await _releaseScreen(previous);
          onChanged();
          await signalVideo(cameraEnabled);
        } catch (_) {
          if (previousCamera != null && wasEnabled != null) {
            previousCamera.enabled = wasEnabled;
          }
          if (acquired != null && acquired != _cameraCapture) {
            await _release(acquired);
          }
          rethrow;
        }
      });

  Future<void> setScreenSharing(bool enabled) => _change(() async {
        if (enabled) {
          MediaStream? acquired;
          try {
            acquired = await openScreen();
            if (_closed) {
              await _releaseScreen(acquired);
              return;
            }
            final track = acquired.getVideoTracks().firstOrNull;
            if (track == null) {
              throw StateError('No shared screen was selected');
            }
            await replaceVideo(track);
            if (_closed) {
              await _releaseScreen(acquired);
              return;
            }
            _screen = acquired;
            track.onEnded = () {
              if (!_closed && sharing) {
                if (busy) {
                  _screenEnded = true;
                } else {
                  unawaited(setScreenSharing(false)
                      .catchError((Object error) => onError(error)));
                }
              }
            };
          } catch (_) {
            if (acquired != null && acquired != _screen) {
              await _releaseScreen(acquired);
            }
            rethrow;
          }
        } else {
          final previous = _screen;
          if (previous == null) return;
          await replaceVideo(cameraEnabled ? _camera : null);
          if (_closed) return;
          _screen = null;
          await _releaseScreen(previous);
        }
        onChanged();
        await signalVideo(sharing || cameraEnabled);
      });

  Future<void> dispose() async {
    _closed = true;
    final screen = _screen;
    _screen = null;
    await _releaseScreen(screen);
    await _release(_cameraCapture);
    _cameraCapture = null;
  }
}
