import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FfmImageHelper {
  FfmImageHelper({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Aturan Mutlak #4: Sisi terpanjang maksimum 1024 px.
  /// Downsample dilakukan langsung oleh platform (iOS/Android) sebelum
  /// bitmap utuh membebani memori Flutter.
  static const double maxImageDimension = 1024.0;

  Future<File?> pickFromCamera() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxImageDimension,
      maxHeight: maxImageDimension,
      imageQuality: 85, // Kompresi wajar untuk OCR
    );
    if (xFile == null) return null;
    return File(xFile.path);
  }

  Future<File?> pickFromGallery() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxImageDimension,
      maxHeight: maxImageDimension,
      imageQuality: 85,
    );
    if (xFile == null) return null;
    return File(xFile.path);
  }

  Future<File> copyToPrivateChatStorage(File source) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'assistant_chat_media'));
    await directory.create(recursive: true);
    final extension = p.extension(source.path).toLowerCase();
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.jpg';
    final target = File(
      p.join(
        directory.path,
        'image_${DateTime.now().microsecondsSinceEpoch}$safeExtension',
      ),
    );
    return source.copy(target.path);
  }
}
