import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ffm_manager/features/assistant/data/ffm_image_helper.dart';

class FakeImagePicker extends ImagePicker {
  FakeImagePicker({this.returnedPath});

  final String? returnedPath;
  ImageSource? lastSource;
  double? lastMaxWidth;
  double? lastMaxHeight;
  int? lastQuality;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    lastSource = source;
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastQuality = imageQuality;

    if (returnedPath == null) return null;
    return XFile(returnedPath!);
  }
}

void main() {
  group('FfmImageHelper', () {
    test(
      'pickFromCamera menggunakan maxWidth/maxHeight 1024 dan source camera',
      () async {
        final picker = FakeImagePicker(returnedPath: '/tmp/cam.jpg');
        final helper = FfmImageHelper(picker: picker);

        final file = await helper.pickFromCamera();

        expect(file?.path, '/tmp/cam.jpg');
        expect(picker.lastSource, ImageSource.camera);
        expect(picker.lastMaxWidth, 1024.0);
        expect(picker.lastMaxHeight, 1024.0);
        expect(picker.lastQuality, 85);
      },
    );

    test(
      'pickFromGallery menggunakan maxWidth/maxHeight 1024 dan source gallery',
      () async {
        final picker = FakeImagePicker(returnedPath: '/tmp/gal.jpg');
        final helper = FfmImageHelper(picker: picker);

        final file = await helper.pickFromGallery();

        expect(file?.path, '/tmp/gal.jpg');
        expect(picker.lastSource, ImageSource.gallery);
        expect(picker.lastMaxWidth, 1024.0);
        expect(picker.lastMaxHeight, 1024.0);
        expect(picker.lastQuality, 85);
      },
    );

    test('mengembalikan null jika pengguna membatalkan picker', () async {
      final picker = FakeImagePicker(returnedPath: null);
      final helper = FfmImageHelper(picker: picker);

      expect(await helper.pickFromCamera(), isNull);
      expect(await helper.pickFromGallery(), isNull);
    });
  });
}
