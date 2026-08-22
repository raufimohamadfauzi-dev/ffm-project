import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan paket model bersifat privat. Model tidak diizinkan mengakses
/// database FFM; status ini hanya menyiapkan file bagi runtime opsional nanti.
class FfmLocalModelInfo {
  const FfmLocalModelInfo({
    required this.fileName,
    required this.filePath,
    required this.bytes,
    required this.sha256,
    required this.installedAt,
  });

  final String fileName;
  final String filePath;
  final int bytes;
  final String sha256;
  final DateTime installedAt;
}

class FfmLocalModelService {
  static const _pathKey = 'ffm_local_model_path';
  static const _nameKey = 'ffm_local_model_name';
  static const _bytesKey = 'ffm_local_model_bytes';
  static const _shaKey = 'ffm_local_model_sha256';
  static const _installedKey = 'ffm_local_model_installed_at';

  Future<FfmLocalModelInfo?> getInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final modelPath = prefs.getString(_pathKey);
    if (modelPath == null) return null;
    final file = File(modelPath);
    if (!await file.exists()) {
      await clear();
      return null;
    }
    final installedAt = DateTime.tryParse(prefs.getString(_installedKey) ?? '');
    return FfmLocalModelInfo(
      fileName: prefs.getString(_nameKey) ?? path.basename(modelPath),
      filePath: modelPath,
      bytes: prefs.getInt(_bytesKey) ?? await file.length(),
      sha256: prefs.getString(_shaKey) ?? await _checksum(file),
      installedAt: installedAt ?? (await file.stat()).modified,
    );
  }

  Future<bool> matchesSha256(String expectedSha256) async {
    final installed = await getInstalled();
    if (installed == null) return false;
    return installed.sha256.toLowerCase() == expectedSha256.toLowerCase();
  }

  Future<FfmLocalModelInfo?> pickAndInstall() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['litertlm', 'task', 'tflite', 'bin'],
    );
    final sourcePath = picked.singleOrNull?.path;
    if (sourcePath == null) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final extension = path.extension(source.path).toLowerCase();
    if (!const ['.litertlm', '.task', '.tflite', '.bin'].contains(extension)) {
      throw const FormatException('Format model belum didukung.');
    }
    final root = await getApplicationSupportDirectory();
    final folder = Directory(path.join(root.path, 'models'));
    await folder.create(recursive: true);
    final destination = File(path.join(folder.path, 'ffm_assistant$extension'));
    await source.copy(destination.path);
    final size = await destination.length();
    if (size < 1024 * 1024) {
      await destination.delete();
      throw const FormatException(
        'File terlalu kecil untuk menjadi paket model.',
      );
    }
    final checksum = await _checksum(destination);
    final installedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathKey, destination.path);
    await prefs.setString(_nameKey, path.basename(source.path));
    await prefs.setInt(_bytesKey, size);
    await prefs.setString(_shaKey, checksum);
    await prefs.setString(_installedKey, installedAt.toIso8601String());
    return FfmLocalModelInfo(
      fileName: path.basename(source.path),
      filePath: destination.path,
      bytes: size,
      sha256: checksum,
      installedAt: installedAt,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final modelPath = prefs.getString(_pathKey);
    if (modelPath != null) {
      final file = File(modelPath);
      if (await file.exists()) await file.delete();
    }
    await prefs.remove(_pathKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_bytesKey);
    await prefs.remove(_shaKey);
    await prefs.remove(_installedKey);
  }

  Future<String> _checksum(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
