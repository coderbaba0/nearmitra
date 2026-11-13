import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

// ZIP encoding/decoding includes synchronous CPU work even in its async APIs.
// Only paths cross the isolate boundary; filesystem work stays off the UI.
Future<void> createFolderArchive(String folderPath, String archivePath) =>
    Isolate.run(() async {
      final encoder = ZipFileEncoder()..create(archivePath);
      try {
        await encoder.addDirectory(Directory(folderPath));
      } finally {
        encoder.close();
      }
    });

Future<void> extractFolderArchive(String archivePath, String destination) =>
    Isolate.run(() => extractFileToDisk(archivePath, destination));
