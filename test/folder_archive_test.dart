import 'dart:io';

import 'package:farmitra_nearby/services/folder_archive_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Worker isolate preserves nested files through folder ZIP round trip',
      () async {
    final root = await Directory.systemTemp.createTemp('folder_worker_test');
    try {
      final source =
          await Directory('${root.path}/source/nested').create(recursive: true);
      await File('${source.path}/message.txt').writeAsString('Phone to phone');
      final archivePath = '${root.path}/folder.zip';
      await createFolderArchive('${root.path}/source', archivePath);
      await extractFolderArchive(archivePath, '${root.path}/received');
      final files = await Directory('${root.path}/received')
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      expect(await files.single.readAsString(), 'Phone to phone');
    } finally {
      await root.delete(recursive: true);
    }
  });
}
