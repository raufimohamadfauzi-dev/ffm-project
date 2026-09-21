import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Owns the private, compressed copies used by assistant conversations.
/// Original gallery/document files are never deleted by this store.
class FfmAssistantAttachmentStore {
  static const _directoryName = 'ffm_assistant_attachments';
  static const _filePrefix = 'attachment_';
  static const _uuid = Uuid();

  FfmAssistantAttachmentStore({this._directoryProvider});

  final Future<Directory> Function()? _directoryProvider;

  Future<Directory> _directory() async {
    final provider = _directoryProvider;
    final root = provider == null
        ? await getApplicationSupportDirectory()
        : await provider();
    final directory = Directory(path.join(root.path, _directoryName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> save(Uint8List bytes, {required String mimeType}) async {
    final directory = await _directory();
    final extension = mimeType == 'image/png' ? 'png' : 'jpg';
    final file = File(
      path.join(directory.path, '$_filePrefix${_uuid.v4()}.$extension'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteManagedPaths(Iterable<String> paths) async {
    final directory = await _directory();
    final directoryPath = path.normalize(directory.path);
    for (final candidate in paths) {
      final filePath = path.normalize(candidate);
      final fileName = path.basename(filePath);
      if (path.dirname(filePath) != directoryPath ||
          !fileName.startsWith(_filePrefix)) {
        continue;
      }
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    }
  }
}
