import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

class FileOpenerService {
  static const MethodChannel _channel = MethodChannel('farmitra_nearby/network');

  /// Check if the file is an Android APK package
  static bool isApkFile(String? path) {
    if (path == null || path.isEmpty) return false;
    final clean = path.split('?').first.split('#').first.toLowerCase();
    return clean.endsWith('.apk');
  }

  /// Open any file, image, document, or install APK directly
  static Future<bool> openOrInstallFile(BuildContext context, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File not found at: $filePath'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }

      // If APK, trigger Android Package Installer
      if (isApkFile(filePath) && Platform.isAndroid) {
        try {
          final res = await _channel.invokeMethod<bool>('installApk', {'path': filePath});
          if (res == true) return true;
        } catch (_) {}

        // Fallback via OpenFilex with explicit MIME type
        final res = await OpenFilex.open(
          filePath,
          type: 'application/vnd.android.package-archive',
        );
        if (res.type == ResultType.done) return true;
      }

      // Standard open for images, audio, video, pdf, docs
      final res = await OpenFilex.open(filePath);
      if (res.type == ResultType.done) return true;

      // Fallback: Copy path if unable to open
      if (context.mounted) {
        Clipboard.setData(ClipboardData(text: filePath));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved: $filePath (Path copied to clipboard)'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'COPY',
              onPressed: () => Clipboard.setData(ClipboardData(text: filePath)),
            ),
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('[FileOpenerService] Error opening file: $e');
      return false;
    }
  }

  /// Open folder in native file manager
  static Future<bool> openFolder(String folderPath) async {
    try {
      if (Platform.isAndroid) {
        final res = await _channel.invokeMethod<bool>('openFolder', {'path': folderPath});
        if (res == true) return true;
      }
      final res = await OpenFilex.open(folderPath);
      return res.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }
}
