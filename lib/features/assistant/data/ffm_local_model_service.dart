import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import 'ffm_staging_status.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kontrak aset Qwen2-VL yang telah diverifikasi pada Fase 0.
class FfmQwen2VlBundle {
  const FfmQwen2VlBundle._();

  static const bundleId = 'qwen2-vl-2b-instruct-iq4-nl-v1';
  static const bundleVersion = 'v1.0.0';
  static const modelFamily = 'Qwen2-VL';
  static const repository = 'raufimohamadfauzi-dev/ffm-project';
  static const releaseTag = 'v1.0.0';

  static const modelFileName = 'Qwen2-VL-2B-Instruct-IQ4_NL.gguf';
  static const projectorFileName = 'mmproj-Qwen2-VL-2B-Instruct-f16.gguf';
  static const manifestFileName = 'verified_manifest.json';

  static const modelUrl =
      'https://github.com/raufimohamadfauzi-dev/ffm-project/releases/download/'
      'v1.0.0/Qwen2-VL-2B-Instruct-IQ4_NL.gguf';
  static const projectorUrl =
      'https://github.com/raufimohamadfauzi-dev/ffm-project/releases/download/'
      'v1.0.0/mmproj-Qwen2-VL-2B-Instruct-f16.gguf';

  static const modelBytes = 936329984;
  static const projectorBytes = 1331656192;
  static const modelSha256 =
      '7df01d764cbb22ce270cd09eb2ff483f7161fcb42b80ea9a93e99d8de4b815e8';
  static const projectorSha256 =
      '05cc3ae461a7b6aa4023312ccab549ecab77cf8677efee04f049fcbab55b8bc3';

  static const files = <FfmModelFileSpec>[
    FfmModelFileSpec(
      role: 'language_model',
      fileName: modelFileName,
      sourceUrl: modelUrl,
      expectedSizeBytes: modelBytes,
      expectedSha256: modelSha256,
    ),
    FfmModelFileSpec(
      role: 'multimodal_projector',
      fileName: projectorFileName,
      sourceUrl: projectorUrl,
      expectedSizeBytes: projectorBytes,
      expectedSha256: projectorSha256,
    ),
  ];
}

class FfmModelFileSpec {
  const FfmModelFileSpec({
    required this.role,
    required this.fileName,
    required this.sourceUrl,
    required this.expectedSizeBytes,
    required this.expectedSha256,
  });

  final String role;
  final String fileName;
  final String sourceUrl;
  final int expectedSizeBytes;
  final String expectedSha256;
}

class FfmModelProgress {
  const FfmModelProgress({
    required this.fileName,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final String fileName;
  final int receivedBytes;
  final int totalBytes;

  double? get fraction => totalBytes <= 0 ? null : receivedBytes / totalBytes;
}

class FfmLocalModelInfo {
  const FfmLocalModelInfo({
    required this.fileName,
    required this.filePath,
    required this.bytes,
    required this.sha256,
    required this.installedAt,
    this.bundleId = FfmQwen2VlBundle.bundleId,
    this.bundleVersion = FfmQwen2VlBundle.bundleVersion,
    this.projectorFileName,
    this.projectorPath,
    this.projectorBytes,
    this.projectorSha256,
    this.manifestPath,
  });

  final String fileName;
  final String filePath;
  final int bytes;
  final String sha256;
  final DateTime installedAt;
  final String bundleId;
  final String bundleVersion;
  final String? projectorFileName;
  final String? projectorPath;
  final int? projectorBytes;
  final String? projectorSha256;
  final String? manifestPath;

  bool get isVerified =>
      bundleId == FfmQwen2VlBundle.bundleId &&
      sha256.toLowerCase() == FfmQwen2VlBundle.modelSha256 &&
      projectorSha256?.toLowerCase() == FfmQwen2VlBundle.projectorSha256;
}

class FfmLocalModelManifestException implements Exception {
  const FfmLocalModelManifestException(this.message);

  final String message;

  @override
  String toString() => 'FfmLocalModelManifestException: $message';
}

class FfmLocalModelDownloadException implements Exception {
  const FfmLocalModelDownloadException(
    this.message, {
    this.canRestart = false,
    this.canRetry = false,
  });

  final String message;
  final bool canRestart;
  final bool canRetry;

  @override
  String toString() => 'FfmLocalModelDownloadException: $message';
}

/// Model Manager lokal. File model tidak pernah disimpan ke Drift/SQLite dan
/// tidak dianggap siap sebelum seluruh bundle tervalidasi dan manifest atomik
/// berhasil ditulis.
class FfmLocalModelService {
  FfmLocalModelService({
    Future<Directory> Function()? applicationSupportDirectory,
    HttpClient Function()? httpClientFactory,
    DateTime Function()? clock,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now;

  static const _legacyPathKey = 'ffm_local_model_path';
  static const _legacyNameKey = 'ffm_local_model_name';
  static const _legacyBytesKey = 'ffm_local_model_bytes';
  static const _legacyShaKey = 'ffm_local_model_sha256';
  static const _legacyInstalledKey = 'ffm_local_model_installed_at';
  static const _downloadFolderName = '.downloads';
  static const _manifestFormat = 'ffm-verified-model-manifest-v1';
  static const _hashChunkSize = 256 * 1024;

  final Future<Directory> Function() _applicationSupportDirectory;
  final HttpClient Function() _httpClientFactory;
  final DateTime Function() _clock;

  Future<Directory> _modelsRoot() async {
    final root = await _applicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'models', 'qwen2-vl'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _finalDirectory() async => Directory(
    path.join((await _modelsRoot()).path, FfmQwen2VlBundle.bundleId),
  );

  Future<Directory> _stagingDirectory() async {
    final root = await _modelsRoot();
    final directory = Directory(
      path.join(root.path, '.staging', FfmQwen2VlBundle.bundleId),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _downloadDirectory() async {
    final root = await _modelsRoot();
    final directory = Directory(path.join(root.path, _downloadFolderName));
    await directory.create(recursive: true);
    return directory;
  }

  Future<FfmStagingStatus> getStagingStatus() async {
    final staging = await _stagingDirectory();
    final modelFile = File(
      path.join(staging.path, FfmQwen2VlBundle.modelFileName),
    );
    final projectorFile = File(
      path.join(staging.path, FfmQwen2VlBundle.projectorFileName),
    );
    return FfmStagingStatus(
      hasModel: await modelFile.exists(),
      hasProjector: await projectorFile.exists(),
    );
  }

  Future<void> clearStaging() async {
    final staging = await _stagingDirectory();
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }

  Future<void> importSingleGguf(PlatformFile selected) async {
    final temporary = File(
      path.join(
        (await _downloadDirectory()).path,
        'picked-${_clock().microsecondsSinceEpoch}.gguf.part',
      ),
    );
    IOSink? sink;
    try {
      if (selected.path != null) {
        await File(selected.path!).copy(temporary.path);
      } else {
        sink = temporary.openWrite();
        await for (final chunk in selected.readAsByteStream()) {
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }

      final hash = await checksum(temporary);
      final staging = await _stagingDirectory();

      if (hash == FfmQwen2VlBundle.modelSha256) {
        await temporary.rename(
          path.join(staging.path, FfmQwen2VlBundle.modelFileName),
        );
      } else if (hash == FfmQwen2VlBundle.projectorSha256) {
        await temporary.rename(
          path.join(staging.path, FfmQwen2VlBundle.projectorFileName),
        );
      } else {
        throw const FfmLocalModelManifestException(
          'File GGUF tidak dikenali atau rusak (hash tidak cocok).',
        );
      }
    } finally {
      await sink?.close();
      await _deleteIfExists(temporary);
    }
  }

  Future<void> importGgufFromPath(
    String filePath, {
    int? expectedBytes,
    int retryAttempts = 3,
    Duration retryDelay = const Duration(milliseconds: 750),
  }) async {
    final file = await _waitForBackgroundFile(
      filePath,
      expectedBytes: expectedBytes,
      retryAttempts: retryAttempts,
      retryDelay: retryDelay,
    );
    final hash = await checksum(file);
    final destinationName = switch (hash) {
      FfmQwen2VlBundle.modelSha256 => FfmQwen2VlBundle.modelFileName,
      FfmQwen2VlBundle.projectorSha256 => FfmQwen2VlBundle.projectorFileName,
      _ => throw const FfmLocalModelManifestException(
        'File hasil download background tidak cocok dengan aset SLM resmi.',
      ),
    };
    final staging = await _stagingDirectory();
    final destination = File(path.join(staging.path, destinationName));
    await file.copy(destination.path);
    await _verifyFile(
      FfmQwen2VlBundle.files.firstWhere(
        (spec) => spec.fileName == destinationName,
      ),
      destination,
    );
    await _deleteIfExists(file);
  }

  /// Ringkasan diagnostik untuk laporan perbaikan. Pemanggil harus
  /// menyimpannya melalui [AppDiagnosticsService] karena layanan itu menyaring
  /// path perangkat sebelum data dapat diekspor.
  Future<String> inspectBackgroundFile(
    String filePath, {
    int? expectedBytes,
  }) async {
    final file = File(filePath);
    final parent = file.parent;
    final exists = await file.exists();
    final actualBytes = exists ? await file.length() : null;
    final parentExists = await parent.exists();
    final children = parentExists
        ? await parent
              .list(followLinks: false)
              .map((entity) => path.basename(entity.path))
              .take(8)
              .toList()
        : const <String>[];
    return 'path=$filePath; fileExists=$exists; actualBytes=${actualBytes ?? 'none'}; '
        'expectedBytes=${expectedBytes ?? 'unknown'}; parentExists=$parentExists; '
        'parentEntries=${children.join('|')}';
  }

  Future<File> _waitForBackgroundFile(
    String filePath, {
    required int? expectedBytes,
    required int retryAttempts,
    required Duration retryDelay,
  }) async {
    final attempts = retryAttempts.clamp(1, 5);
    final file = File(filePath);
    String? lastState;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      if (await file.exists()) {
        final actualBytes = await file.length();
        if (expectedBytes == null ||
            expectedBytes <= 0 ||
            actualBytes == expectedBytes) {
          return file;
        }
        lastState =
            'ukuran file $actualBytes byte, menunggu $expectedBytes byte';
      } else {
        lastState = 'file belum terlihat di storage aplikasi';
      }
      if (attempt < attempts) await Future<void>.delayed(retryDelay);
    }
    throw FfmLocalModelManifestException(
      'File download background belum stabil setelah $attempts pemeriksaan: ${lastState ?? 'status file tidak diketahui'}. Tekan Perbarui status untuk mencoba lagi.',
    );
  }

  Future<FfmLocalModelInfo> commitStaging() async {
    final status = await getStagingStatus();
    if (!status.isReadyToCommit) {
      throw const FfmLocalModelManifestException(
        'File di staging belum lengkap.',
      );
    }

    final staging = await _stagingDirectory();
    final modelFile = File(
      path.join(staging.path, FfmQwen2VlBundle.modelFileName),
    );
    final projectorFile = File(
      path.join(staging.path, FfmQwen2VlBundle.projectorFileName),
    );

    await _verifyFile(FfmQwen2VlBundle.files[0], modelFile);
    await _verifyFile(FfmQwen2VlBundle.files[1], projectorFile);

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': _manifestFormat,
        'bundleId': FfmQwen2VlBundle.bundleId,
        'bundleVersion': FfmQwen2VlBundle.bundleVersion,
        'modelFamily': FfmQwen2VlBundle.modelFamily,
        'verificationStatus': 'verified',
        'verifiedAtUtc': _clock().toUtc().toIso8601String(),
        'files': [
          {
            'role': FfmQwen2VlBundle.files[0].role,
            'fileName': FfmQwen2VlBundle.files[0].fileName,
            'expectedSha256': FfmQwen2VlBundle.files[0].expectedSha256,
            'actualSha256': FfmQwen2VlBundle.files[0].expectedSha256,
            'actualSizeBytes': '${FfmQwen2VlBundle.files[0].expectedSizeBytes}',
            'ggufHeaderVerified': true,
          },
          {
            'role': FfmQwen2VlBundle.files[1].role,
            'fileName': FfmQwen2VlBundle.files[1].fileName,
            'expectedSha256': FfmQwen2VlBundle.files[1].expectedSha256,
            'actualSha256': FfmQwen2VlBundle.files[1].expectedSha256,
            'actualSizeBytes': '${FfmQwen2VlBundle.files[1].expectedSizeBytes}',
            'ggufHeaderVerified': true,
          },
        ],
      }),
    );

    await File(path.join(staging.path, FfmQwen2VlBundle.manifestFileName))
        .writeAsBytes(manifestBytes, flush: true);

    final finalDirectory = await _finalDirectory();
    final backup = Directory('${finalDirectory.path}.previous');
    if (await backup.exists()) await backup.delete(recursive: true);
    if (await finalDirectory.exists()) await finalDirectory.rename(backup.path);

    await staging.rename(finalDirectory.path);

    if (await backup.exists()) await backup.delete(recursive: true);

    final installed = await getInstalled();
    if (installed == null) {
      throw const FfmLocalModelManifestException(
        'Commit gagal, manifest tidak terbaca setelah dipindahkan.',
      );
    }
    return installed;
  }

  Future<FfmLocalModelInfo?> getInstalled() async {
    final finalDirectory = await _finalDirectory();
    final manifestFile = File(
      path.join(finalDirectory.path, FfmQwen2VlBundle.manifestFileName),
    );
    if (!await manifestFile.exists()) return null;

    try {
      final manifest = await _readManifest(manifestFile);
      if (manifest['bundleId'] != FfmQwen2VlBundle.bundleId ||
          manifest['verificationStatus'] != 'verified') {
        return null;
      }
      final files = _manifestFiles(manifest);
      final model = files.firstWhere(
        (file) => file['role'] == 'language_model',
        orElse: () => <String, dynamic>{},
      );
      final projector = files.firstWhere(
        (file) => file['role'] == 'multimodal_projector',
        orElse: () => <String, dynamic>{},
      );
      if (model.isEmpty ||
          projector.isEmpty ||
          model['fileName'] != FfmQwen2VlBundle.modelFileName ||
          projector['fileName'] != FfmQwen2VlBundle.projectorFileName ||
          model['expectedSizeBytes'] != '${FfmQwen2VlBundle.modelBytes}' ||
          projector['expectedSizeBytes'] !=
              '${FfmQwen2VlBundle.projectorBytes}' ||
          model['actualSizeBytes'] != '${FfmQwen2VlBundle.modelBytes}' ||
          projector['actualSizeBytes'] !=
              '${FfmQwen2VlBundle.projectorBytes}' ||
          model['expectedSha256'] != FfmQwen2VlBundle.modelSha256 ||
          projector['expectedSha256'] != FfmQwen2VlBundle.projectorSha256 ||
          model['actualSha256'] != FfmQwen2VlBundle.modelSha256 ||
          projector['actualSha256'] != FfmQwen2VlBundle.projectorSha256 ||
          model['ggufHeaderVerified'] != true ||
          projector['ggufHeaderVerified'] != true) {
        return null;
      }

      final modelFile = _safeChild(
        finalDirectory,
        model['fileName'] as String?,
      );
      final projectorFile = _safeChild(
        finalDirectory,
        projector['fileName'] as String?,
      );
      if (modelFile == null || projectorFile == null) return null;
      if (!await modelFile.exists() || !await projectorFile.exists())
        return null;

      final modelBytes = int.tryParse('${model['actualSizeBytes']}');
      final projectorBytes = int.tryParse('${projector['actualSizeBytes']}');
      if (modelBytes == null ||
          projectorBytes == null ||
          await modelFile.length() != modelBytes ||
          await projectorFile.length() != projectorBytes) {
        return null;
      }

      final installedAt =
          DateTime.tryParse('${manifest['verifiedAtUtc']}') ??
          (await modelFile.stat()).modified;
      return FfmLocalModelInfo(
        fileName: path.basename(modelFile.path),
        filePath: modelFile.path,
        bytes: modelBytes,
        sha256: '${model['actualSha256']}',
        installedAt: installedAt,
        bundleId: '${manifest['bundleId']}',
        bundleVersion: '${manifest['bundleVersion']}',
        projectorFileName: path.basename(projectorFile.path),
        projectorPath: projectorFile.path,
        projectorBytes: projectorBytes,
        projectorSha256: '${projector['actualSha256']}',
        manifestPath: manifestFile.path,
      );
    } on Object {
      return null;
    }
  }

  /// Memvalidasi hash kedua file secara streaming. Pemeriksaan ini sengaja
  /// eksplisit karena membuka model tidak boleh memuat seluruh file ke RAM.
  Future<FfmLocalModelInfo?> verifyInstalled() async {
    final installed = await getInstalled();
    if (installed == null || installed.projectorPath == null) return null;
    final modelHash = await checksum(File(installed.filePath));
    final projectorHash = await checksum(File(installed.projectorPath!));
    if (modelHash != FfmQwen2VlBundle.modelSha256 ||
        projectorHash != FfmQwen2VlBundle.projectorSha256) {
      return null;
    }
    return installed;
  }

  Future<bool> matchesSha256(String expectedSha256) async {
    final installed = await getInstalled();
    if (installed == null) return false;
    return installed.sha256.toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Mengunduh satu bundle secara berurutan. Resume hanya dilakukan bila
  /// server membalas 206 dan metadata aset tidak berubah. File `.part` tidak
  /// pernah dipindahkan ke folder final sebelum verifikasi selesai.
  Future<FfmLocalModelInfo> downloadBundle({
    void Function(FfmModelProgress progress)? onProgress,
    bool restartPartial = false,
  }) async {
    final downloadRoot = await _downloadDirectory();
    final bundleDownload = Directory(
      path.join(downloadRoot.path, FfmQwen2VlBundle.bundleId),
    );
    await bundleDownload.create(recursive: true);

    final verifiedParts = <File>[];
    try {
      for (final spec in FfmQwen2VlBundle.files) {
        final part = File(
          path.join(bundleDownload.path, '${spec.fileName}.part'),
        );
        final metadata = File(
          path.join(bundleDownload.path, '${spec.fileName}.resume.json'),
        );
        var alreadyVerified = false;
        if (await part.exists() &&
            await part.length() == spec.expectedSizeBytes) {
          try {
            await _verifyFile(spec, part);
            alreadyVerified = true;
          } on Object {
            if (!restartPartial) {
              throw FfmLocalModelDownloadException(
                '${spec.fileName}: file parsial berukuran penuh tetapi hash tidak cocok. Mulai ulang secara eksplisit.',
                canRestart: true,
              );
            }
            await part.delete();
            if (await metadata.exists()) await metadata.delete();
          }
        }
        if (!alreadyVerified) {
          await _downloadFile(
            spec,
            part,
            metadata,
            onProgress: onProgress,
            restartPartial: restartPartial,
          );
          await _verifyFile(spec, part);
        }
        verifiedParts.add(part);
      }

      final staging = Directory(
        path.join(downloadRoot.path, '${FfmQwen2VlBundle.bundleId}.ready'),
      );
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final actualFiles = <Map<String, dynamic>>[];
      for (var index = 0; index < FfmQwen2VlBundle.files.length; index++) {
        final spec = FfmQwen2VlBundle.files[index];
        final source = verifiedParts[index];
        final destination = File(path.join(staging.path, spec.fileName));
        await source.rename(destination.path);
        actualFiles.add({
          'role': spec.role,
          'fileName': spec.fileName,
          'localRelativePath': spec.fileName,
          'sourceUrl': spec.sourceUrl,
          'expectedSizeBytes': '${spec.expectedSizeBytes}',
          'expectedSha256': spec.expectedSha256,
          'actualSizeBytes': '${await destination.length()}',
          'actualSha256': await checksum(destination),
          'ggufHeaderVerified': await _hasValidGgufHeader(destination),
        });
      }

      final manifest = <String, dynamic>{
        'formatVersion': _manifestFormat,
        'bundleId': FfmQwen2VlBundle.bundleId,
        'bundleVersion': FfmQwen2VlBundle.bundleVersion,
        'modelFamily': FfmQwen2VlBundle.modelFamily,
        'verificationStatus': 'verified',
        'verifiedAtUtc': _clock().toUtc().toIso8601String(),
        'storageRoot': 'models/qwen2-vl/${FfmQwen2VlBundle.bundleId}',
        'source': {
          'kind': 'download',
          'repository': FfmQwen2VlBundle.repository,
          'releaseTag': FfmQwen2VlBundle.releaseTag,
        },
        'files': actualFiles,
      };
      await _writeJsonAtomically(
        File(path.join(staging.path, FfmQwen2VlBundle.manifestFileName)),
        manifest,
      );

      final finalDirectory = await _finalDirectory();
      final backup = Directory('${finalDirectory.path}.previous');
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await finalDirectory.exists())
        await finalDirectory.rename(backup.path);
      await staging.rename(finalDirectory.path);
      if (await backup.exists()) await backup.delete(recursive: true);
      await bundleDownload.delete(recursive: true);

      final installed = await getInstalled();
      if (installed == null) {
        throw const FfmLocalModelManifestException(
          'Manifest model terverifikasi tidak dapat dibaca setelah pemasangan.',
        );
      }
      return installed;
    } catch (_) {
      // Semua `.part` dan metadata resume dipertahankan untuk pemulihan.
      rethrow;
    }
  }

  Future<File> exportVerifiedBundle({Directory? outputDirectory}) async {
    final installed = await verifyInstalled();
    if (installed == null ||
        installed.manifestPath == null ||
        installed.projectorPath == null) {
      throw const FfmLocalModelManifestException(
        'Bundle lokal belum terverifikasi penuh dan tidak dapat diekspor.',
      );
    }
    final directory =
        outputDirectory ??
        Directory(path.join((await _modelsRoot()).path, 'exports'));
    await directory.create(recursive: true);
    final output = File(
      path.join(
        directory.path,
        '${FfmQwen2VlBundle.bundleId}-${FfmQwen2VlBundle.bundleVersion}.ffmbundle',
      ),
    );
    final temporary = File('${output.path}.tmp');
    await _deleteIfExists(temporary);
    final encoder = ZipFileEncoder();
    encoder.create(temporary.path, level: ZipFileEncoder.STORE);
    await encoder.addFile(
      File(installed.manifestPath!),
      FfmQwen2VlBundle.manifestFileName,
      ZipFileEncoder.STORE,
    );
    await encoder.addFile(
      File(installed.filePath),
      FfmQwen2VlBundle.modelFileName,
      ZipFileEncoder.STORE,
    );
    await encoder.addFile(
      File(installed.projectorPath!),
      FfmQwen2VlBundle.projectorFileName,
      ZipFileEncoder.STORE,
    );
    await encoder.close();
    await _deleteIfExists(output);
    await temporary.rename(output.path);
    return output;
  }

  Future<FfmLocalModelInfo> importBundle(File bundleFile) async {
    if (!await bundleFile.exists()) {
      throw const FfmLocalModelManifestException(
        'File bundle tidak ditemukan.',
      );
    }
    final entries = await _readZipEntries(bundleFile);
    final byName = <String, _FfmZipEntry>{
      for (final entry in entries) entry.name: entry,
    };
    const requiredNames = <String>{
      FfmQwen2VlBundle.manifestFileName,
      FfmQwen2VlBundle.modelFileName,
      FfmQwen2VlBundle.projectorFileName,
    };
    if (!byName.keys.toSet().containsAll(requiredNames)) {
      throw const FfmLocalModelManifestException(
        'Bundle tidak berisi manifest dan dua aset GGUF yang diwajibkan.',
      );
    }
    final manifestBytes = await _readZipEntryBytes(
      bundleFile,
      byName[FfmQwen2VlBundle.manifestFileName]!,
      maxBytes: 1024 * 1024,
    );
    final decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['formatVersion'] != _manifestFormat ||
        decoded['bundleId'] != FfmQwen2VlBundle.bundleId) {
      throw const FfmLocalModelManifestException(
        'Manifest bundle offline tidak cocok dengan kontrak Qwen2-VL FFM.',
      );
    }
    final manifestFiles = _manifestFiles(decoded);
    final specsByRole = <String, FfmModelFileSpec>{
      for (final spec in FfmQwen2VlBundle.files) spec.role: spec,
    };
    for (final spec in FfmQwen2VlBundle.files) {
      final record = manifestFiles.firstWhere(
        (item) => item['role'] == spec.role,
        orElse: () => <String, dynamic>{},
      );
      if (record.isEmpty ||
          record['fileName'] != spec.fileName ||
          record['expectedSha256'] != spec.expectedSha256 ||
          record['actualSha256'] != spec.expectedSha256 ||
          record['actualSizeBytes'] != '${spec.expectedSizeBytes}' ||
          record['ggufHeaderVerified'] != true) {
        throw FfmLocalModelManifestException(
          'Manifest tidak valid untuk ${spec.fileName}.',
        );
      }
    }
    if (specsByRole.length != FfmQwen2VlBundle.files.length) {
      throw const FfmLocalModelManifestException(
        'Spesifikasi bundle tidak lengkap.',
      );
    }

    final root = await _downloadDirectory();
    final staging = Directory(
      path.join(
        root.path,
        '${FfmQwen2VlBundle.bundleId}.import-${_clock().microsecondsSinceEpoch}',
      ),
    );
    await staging.create(recursive: true);
    try {
      for (final spec in FfmQwen2VlBundle.files) {
        final entry = byName[spec.fileName]!;
        if (entry.compressionMethod != 0 ||
            entry.compressedSize != spec.expectedSizeBytes ||
            entry.uncompressedSize != spec.expectedSizeBytes) {
          throw FfmLocalModelManifestException(
            '${spec.fileName}: bundle harus memakai entry ZIP store yang ukurannya sesuai.',
          );
        }
        final destination = File(path.join(staging.path, spec.fileName));
        await _extractStoreEntry(bundleFile, entry, destination);
        await _verifyFile(spec, destination);
      }
      await File(path.join(staging.path, FfmQwen2VlBundle.manifestFileName))
          .writeAsBytes(manifestBytes, flush: true);
      final finalDirectory = await _finalDirectory();
      final backup = Directory('${finalDirectory.path}.previous');
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await finalDirectory.exists())
        await finalDirectory.rename(backup.path);
      await staging.rename(finalDirectory.path);
      if (await backup.exists()) await backup.delete(recursive: true);
      final installed = await getInstalled();
      if (installed == null) {
        throw const FfmLocalModelManifestException(
          'Bundle telah dipindahkan tetapi manifest tidak lolos pemeriksaan akhir.',
        );
      }
      return installed;
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<FfmLocalModelInfo?> pickAndInstallBundle() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ffmbundle', 'zip'],
    );
    final selected = picked.singleOrNull;
    if (selected == null) return null;
    return _importPickedFile(selected);
  }

  Future<FfmLocalModelInfo> _importPickedFile(PlatformFile selected) async {
    final sourcePath = selected.path;
    if (sourcePath != null) return importBundle(File(sourcePath));

    // Android Storage Access Framework dapat mengembalikan content:// URI
    // tanpa path filesystem. Salin melalui stream agar bundle 2+ GB tidak
    // dimuat seluruhnya ke RAM dan tetap berada di storage privat aplikasi.
    final temporary = File(
      path.join(
        (await _downloadDirectory()).path,
        'picked-${_clock().microsecondsSinceEpoch}.ffmbundle.part',
      ),
    );
    IOSink? sink;
    try {
      sink = temporary.openWrite();
      await for (final chunk in selected.readAsByteStream()) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return await importBundle(temporary);
    } finally {
      await sink?.close();
      await _deleteIfExists(temporary);
    }
  }

  Future<void> resetPartialDownload() async {
    final downloadRoot = await _downloadDirectory();
    final bundleDownload = Directory(
      path.join(downloadRoot.path, FfmQwen2VlBundle.bundleId),
    );
    if (await bundleDownload.exists())
      await bundleDownload.delete(recursive: true);
  }

  Future<void> clear() async {
    final finalDirectory = await _finalDirectory();
    if (await finalDirectory.exists())
      await finalDirectory.delete(recursive: true);
    await resetPartialDownload();

    // Bersihkan format provisional v47 bila pernah dipakai pada instalasi lama.
    final prefs = await SharedPreferences.getInstance();
    final legacyPath = prefs.getString(_legacyPathKey);
    if (legacyPath != null) {
      final legacyFile = File(legacyPath);
      if (await legacyFile.exists()) await legacyFile.delete();
    }
    await prefs.remove(_legacyPathKey);
    await prefs.remove(_legacyNameKey);
    await prefs.remove(_legacyBytesKey);
    await prefs.remove(_legacyShaKey);
    await prefs.remove(_legacyInstalledKey);
  }

  /// Dipertahankan sementara agar build halaman lama tetap kompatibel. Jalur
  /// produksi baru memakai [downloadBundle] dan hanya menerima bundle Qwen
  /// yang memiliki manifest verified.
  @Deprecated(
    'Gunakan pickAndInstallBundle untuk bundle Qwen2-VL terverifikasi.',
  )
  Future<FfmLocalModelInfo?> pickAndInstall() => pickAndInstallBundle();

  Future<List<_FfmZipEntry>> _readZipEntries(File file) async {
    final length = await file.length();
    if (length < 22) {
      throw const FfmLocalModelManifestException('Bundle ZIP terlalu kecil.');
    }
    final handle = await file.open();
    try {
      final tailStart = length > 65557 ? length - 65557 : 0;
      await handle.setPosition(tailStart);
      final tail = await handle.read(length - tailStart);
      var eocd = -1;
      for (var index = tail.length - 22; index >= 0; index--) {
        if (_u32(tail, index) == 0x06054b50) {
          eocd = index;
          break;
        }
      }
      if (eocd < 0) {
        throw const FfmLocalModelManifestException(
          'End of central directory ZIP tidak ditemukan.',
        );
      }
      final count = _u16(tail, eocd + 10);
      final centralSize = _u32(tail, eocd + 12);
      final centralOffset = _u32(tail, eocd + 16);
      if (centralSize > 16 * 1024 * 1024) {
        throw const FfmLocalModelManifestException(
          'Central directory bundle terlalu besar.',
        );
      }
      await handle.setPosition(centralOffset);
      final central = await handle.read(centralSize);
      final entries = <_FfmZipEntry>[];
      var cursor = 0;
      for (var index = 0; index < count; index++) {
        if (cursor + 46 > central.length ||
            _u32(central, cursor) != 0x02014b50) {
          throw const FfmLocalModelManifestException(
            'Central directory ZIP rusak.',
          );
        }
        final compressionMethod = _u16(central, cursor + 10);
        final compressedSize = _u32(central, cursor + 20);
        final uncompressedSize = _u32(central, cursor + 24);
        final nameLength = _u16(central, cursor + 28);
        final extraLength = _u16(central, cursor + 30);
        final commentLength = _u16(central, cursor + 32);
        final localHeaderOffset = _u32(central, cursor + 42);
        final nameEnd = cursor + 46 + nameLength;
        if (nameEnd + extraLength + commentLength > central.length) {
          throw const FfmLocalModelManifestException(
            'Entry ZIP berada di luar central directory.',
          );
        }
        final name = utf8.decode(central.sublist(cursor + 46, nameEnd));
        if (name.isEmpty ||
            name.contains('..') ||
            name.startsWith('/') ||
            name.contains('\\')) {
          throw const FfmLocalModelManifestException(
            'Nama file bundle tidak aman.',
          );
        }
        entries.add(
          _FfmZipEntry(
            name: name,
            compressionMethod: compressionMethod,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            localHeaderOffset: localHeaderOffset,
          ),
        );
        cursor = nameEnd + extraLength + commentLength;
      }
      return entries;
    } finally {
      await handle.close();
    }
  }

  Future<List<int>> _readZipEntryBytes(
    File bundle,
    _FfmZipEntry entry, {
    required int maxBytes,
  }) async {
    if (entry.compressionMethod != 0 || entry.uncompressedSize > maxBytes) {
      throw const FfmLocalModelManifestException(
        'Entry manifest ZIP tidak dapat dibaca aman.',
      );
    }
    final handle = await bundle.open();
    try {
      final dataOffset = await _zipDataOffset(handle, entry);
      await handle.setPosition(dataOffset);
      return await handle.read(entry.uncompressedSize);
    } finally {
      await handle.close();
    }
  }

  Future<void> _extractStoreEntry(
    File bundle,
    _FfmZipEntry entry,
    File destination,
  ) async {
    final handle = await bundle.open();
    IOSink? sink;
    try {
      final dataOffset = await _zipDataOffset(handle, entry);
      await handle.setPosition(dataOffset);
      sink = destination.openWrite();
      var remaining = entry.uncompressedSize;
      while (remaining > 0) {
        final chunk = await handle.read(
          remaining > _hashChunkSize ? _hashChunkSize : remaining,
        );
        if (chunk.isEmpty)
          throw const FfmLocalModelManifestException('Entry ZIP terpotong.');
        sink.add(chunk);
        remaining -= chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      await sink?.close();
      await handle.close();
    }
  }

  Future<int> _zipDataOffset(
    RandomAccessFile handle,
    _FfmZipEntry entry,
  ) async {
    await handle.setPosition(entry.localHeaderOffset);
    final header = await handle.read(30);
    if (header.length < 30 || _u32(header, 0) != 0x04034b50) {
      throw const FfmLocalModelManifestException('Local header ZIP rusak.');
    }
    final nameLength = _u16(header, 26);
    final extraLength = _u16(header, 28);
    return entry.localHeaderOffset + 30 + nameLength + extraLength;
  }

  static int _u16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _u32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  Future<void> _downloadFile(
    FfmModelFileSpec spec,
    File part,
    File resumeMetadata, {
    void Function(FfmModelProgress progress)? onProgress,
    required bool restartPartial,
  }) async {
    var existingBytes = await part.exists() ? await part.length() : 0;
    Map<String, dynamic> previous = <String, dynamic>{};
    if (await resumeMetadata.exists()) {
      try {
        previous = jsonDecode(
          await resumeMetadata.readAsString(),
        ) as Map<String, dynamic>;
      } on Object {
        previous = <String, dynamic>{};
      }
    }
    final metadataMatches =
        previous['bundleId'] == FfmQwen2VlBundle.bundleId &&
        previous['fileName'] == spec.fileName &&
        previous['expectedSizeBytes'] == spec.expectedSizeBytes &&
        previous['expectedSha256'] == spec.expectedSha256;
    if (existingBytes > 0 && !metadataMatches) {
      if (!restartPartial) {
        throw const FfmLocalModelDownloadException(
          'File parsial tidak memiliki metadata aset yang cocok. Hapus unduhan parsial lalu mulai ulang.',
          canRestart: true,
        );
      }
      await _deleteIfExists(part);
      await _deleteIfExists(resumeMetadata);
      existingBytes = 0;
    }
    if (existingBytes > spec.expectedSizeBytes) {
      if (!restartPartial) {
        throw const FfmLocalModelDownloadException(
          'File parsial lebih besar dari ukuran aset. Hapus unduhan parsial lalu mulai ulang.',
          canRestart: true,
        );
      }
      await _deleteIfExists(part);
      existingBytes = 0;
    }

    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 30);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(spec.sourceUrl));
      request.followRedirects = true;
      request.maxRedirects = 5;
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
        final etag = previous['etag'];
        final lastModified = previous['lastModified'];
        if (etag is String && etag.isNotEmpty) {
          request.headers.set('If-Range', etag);
        } else if (lastModified is String && lastModified.isNotEmpty) {
          request.headers.set('If-Range', lastModified);
        }
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw const FfmLocalModelDownloadException(
          'Koneksi download timeout. Periksa internet lalu coba lagi.',
          canRestart: true,
        ),
      );
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final lastModified = response.headers.value(
        HttpHeaders.lastModifiedHeader,
      );
      final responseLength = response.contentLength;
      final previousEtag = previous['etag'];
      final previousLastModified = previous['lastModified'];
      final resumeMarkerChanged =
          existingBytes > 0 &&
          ((previousEtag is String &&
                  previousEtag.isNotEmpty &&
                  etag != previousEtag) ||
              (previousEtag is! String &&
                  previousLastModified is String &&
                  previousLastModified.isNotEmpty &&
                  lastModified != previousLastModified));
      if (resumeMarkerChanged) {
        if (!restartPartial) {
          throw const FfmLocalModelDownloadException(
            'ETag atau Last-Modified aset berubah. Pilih Mulai ulang secara eksplisit.',
            canRestart: true,
          );
        }
        await _deleteIfExists(part);
        await _deleteIfExists(resumeMetadata);
        return await _downloadFile(
          spec,
          part,
          resumeMetadata,
          onProgress: onProgress,
          restartPartial: false,
        );
      }

      if (existingBytes > 0 &&
          response.statusCode != HttpStatus.partialContent) {
        if (!restartPartial) {
          throw const FfmLocalModelDownloadException(
            'Server tidak mengizinkan resume unduhan ini. Pilih Mulai ulang secara eksplisit.',
            canRestart: true,
          );
        }
        await _deleteIfExists(part);
        await _deleteIfExists(resumeMetadata);
        return await _downloadFile(
          spec,
          part,
          resumeMetadata,
          onProgress: onProgress,
          restartPartial: false,
        );
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw FfmLocalModelDownloadException(
          'Unduhan ${spec.fileName} gagal dengan HTTP ${response.statusCode}.',
        );
      }

      final append = existingBytes > 0;
      if (append &&
          responseLength >= 0 &&
          existingBytes + responseLength > spec.expectedSizeBytes) {
        throw const FfmLocalModelDownloadException(
          'Ukuran respons resume melebihi ukuran aset yang diharapkan.',
          canRestart: true,
        );
      }
      await _writeJsonAtomically(resumeMetadata, {
        'bundleId': FfmQwen2VlBundle.bundleId,
        'fileName': spec.fileName,
        'expectedSizeBytes': spec.expectedSizeBytes,
        'expectedSha256': spec.expectedSha256,
        'etag': etag,
        'lastModified': lastModified,
      });
      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var received = append ? existingBytes : 0;
      await for (final chunk in response.timeout(
        const Duration(minutes: 2),
        onTimeout: (_) => throw const FfmLocalModelDownloadException(
          'Download tidak menerima data selama 2 menit. Coba lagi atau mulai ulang.',
          canRestart: true,
        ),
      )) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          FfmModelProgress(
            fileName: spec.fileName,
            receivedBytes: received,
            totalBytes: spec.expectedSizeBytes,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await _deleteIfExists(resumeMetadata);
    } on FfmLocalModelDownloadException {
      rethrow;
    } catch (error) {
      if (error is SocketException) {
        throw FfmLocalModelDownloadException(
          'Tidak bisa menghubungi GitHub dari HP ini. Periksa internet, '
          'Private DNS, atau VPN; lalu pilih Coba lagi. File unduhan parsial '
          'tetap disimpan agar tidak mulai dari nol. Jika jaringan tetap tidak '
          'tersedia, gunakan Impor bundle offline.',
          canRetry: true,
        );
      }
      throw FfmLocalModelDownloadException(
        'Unduhan ${spec.fileName} terhenti: $error',
        canRestart: true,
      );
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _verifyFile(FfmModelFileSpec spec, File file) async {
    final actualBytes = await file.length();
    if (actualBytes != spec.expectedSizeBytes) {
      throw FfmLocalModelManifestException(
        '${spec.fileName}: ukuran $actualBytes tidak sama dengan ${spec.expectedSizeBytes}.',
      );
    }
    final actualHash = await checksum(file);
    if (actualHash != spec.expectedSha256) {
      throw FfmLocalModelManifestException(
        '${spec.fileName}: SHA-256 tidak cocok.',
      );
    }
    if (!await _hasValidGgufHeader(file)) {
      throw FfmLocalModelManifestException(
        '${spec.fileName}: header GGUF tidak valid.',
      );
    }
  }

  Future<String> checksum(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    final handle = await file.open();
    try {
      while (true) {
        final chunk = await handle.read(_hashChunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
      input.close();
      return output.events.single.toString();
    } finally {
      await handle.close();
    }
  }

  Future<bool> _hasValidGgufHeader(File file) async {
    final handle = await file.open();
    try {
      final header = await handle.read(8);
      if (header.length < 8) return false;
      return String.fromCharCodes(header.sublist(0, 4)) == 'GGUF' &&
          ByteData.sublistView(
                Uint8List.fromList(header),
                4,
                8,
              ).getUint32(0, Endian.little) ==
              3;
    } finally {
      await handle.close();
    }
  }

  Future<Map<String, dynamic>> _readManifest(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['formatVersion'] != _manifestFormat) {
      throw const FfmLocalModelManifestException(
        'Format manifest tidak dikenal.',
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _manifestFiles(Map<String, dynamic> manifest) {
    final raw = manifest['files'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  File? _safeChild(Directory parent, String? fileName) {
    if (fileName == null ||
        fileName.isEmpty ||
        path.basename(fileName) != fileName) {
      return null;
    }
    return File(path.join(parent.path, fileName));
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, dynamic> value,
  ) async {
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

class _FfmZipEntry {
  const _FfmZipEntry({
    required this.name,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String name;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
}
