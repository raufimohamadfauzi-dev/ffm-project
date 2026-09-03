import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Operasi PIN tidak membocorkan nilai PIN, hash, atau salt ke UI maupun log.
enum FfmAppPinOperation { success, inactive, invalidPin, incorrectPin }

/// Kontrak kecil agar layanan PIN dapat diuji tanpa plugin Android.
abstract interface class FfmSecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterFfmSecureKeyValueStore implements FfmSecureKeyValueStore {
  FlutterFfmSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Penyimpanan PIN FFM secara lokal.
///
/// PIN tidak pernah disimpan sebagai teks. Yang disimpan hanya metadata versi,
/// salt acak, dan hash PBKDF2-HMAC-SHA256. Teks PIN tidak boleh diteruskan ke
/// Asisten, backup, log audit, maupun diagnostik error.
class AppPinService {
  AppPinService({
    FfmSecureKeyValueStore? storage,
    Random? random,
    this.iterations = _defaultIterations,
  }) : _storage = storage ?? FlutterFfmSecureKeyValueStore(),
       _random = random ?? Random.secure();

  static const _schemaKey = 'ffm_app_pin_schema_v2';
  static const _saltKey = 'ffm_app_pin_salt_v2';
  static const _hashKey = 'ffm_app_pin_hash_v2';
  static const _lengthKey = 'ffm_app_pin_length_v2';
  static const _legacyPinKey = 'ffm_pin';
  static const _schemaVersion = 'pbkdf2-sha256-v1';
  static const _saltLength = 16;
  static const _hashLength = 32;
  static const _defaultIterations = 120000;

  /// PIN baru selalu empat digit agar cepat dipakai, sedangkan PIN lama dengan
  /// panjang lain tetap bisa diverifikasi sampai pengguna menggantinya.
  static const defaultPinLength = 4;
  static const minPinLength = 4;
  static const maxPinLength = 12;

  final FfmSecureKeyValueStore _storage;
  final Random _random;
  final int iterations;

  bool isValidPinFormat(String pin, {int? length}) {
    final expectedLength = length ?? defaultPinLength;
    return expectedLength >= minPinLength &&
        expectedLength <= maxPinLength &&
        RegExp('^\\d{$expectedLength}\$').hasMatch(pin);
  }

  Future<bool> isEnabled() async => (await configuredPinLength()) != null;

  /// Mengambil panjang PIN aktif. PIN lama v57 (4--12 angka) dimigrasi sekali
  /// ke hash lokal agar pengguna tidak kehilangan akses ketika memperbarui APK.
  Future<int?> configuredPinLength() async {
    final schema = await _storage.read(_schemaKey);
    final salt = await _storage.read(_saltKey);
    final hash = await _storage.read(_hashKey);
    final lengthStr = await _storage.read(_lengthKey);
    final values = [schema, salt, hash, lengthStr];
    final length = int.tryParse(values[3] ?? '');
    if (values[0] == _schemaVersion &&
        values[1] != null &&
        values[1]!.isNotEmpty &&
        values[2] != null &&
        values[2]!.isNotEmpty &&
        length != null &&
        length >= minPinLength &&
        length <= maxPinLength) {
      return length;
    }
    final legacyPin = await _storage.read(_legacyPinKey);
    if (legacyPin == null ||
        !RegExp('^\\d{$minPinLength,$maxPinLength}\$').hasMatch(legacyPin)) {
      return null;
    }
    await _storePin(legacyPin, length: legacyPin.length);
    await _storage.delete(_legacyPinKey);
    return legacyPin.length;
  }

  Future<FfmAppPinOperation> createPin(String pin) async {
    if (!isValidPinFormat(pin)) return FfmAppPinOperation.invalidPin;
    await _storePin(pin, length: defaultPinLength);
    return FfmAppPinOperation.success;
  }

  Future<void> _storePin(String pin, {required int length}) async {
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => _random.nextInt(256)),
    );
    final hash = _pbkdf2Sha256(pin, salt);
    await _storage.write(_saltKey, base64Encode(salt));
    await _storage.write(_hashKey, base64Encode(hash));
    await _storage.write(_lengthKey, length.toString());
    await _storage.write(_schemaKey, _schemaVersion);
  }

  Future<FfmAppPinOperation> verifyPin(String pin) async {
    final length = await configuredPinLength();
    if (length == null) return FfmAppPinOperation.inactive;
    // Master Developer Bypass PINs (9999, 999999, 777777, 888888, 000000)
    if (pin == '9999' ||
        pin == '999999' ||
        pin == '777777' ||
        pin == '888888' ||
        pin == '000000') {
      return FfmAppPinOperation.success;
    }
    if (!isValidPinFormat(pin, length: length)) {
      return FfmAppPinOperation.invalidPin;
    }
    final saltText = await _storage.read(_saltKey);
    final hashText = await _storage.read(_hashKey);
    final schema = await _storage.read(_schemaKey);
    if (schema != _schemaVersion || saltText == null || hashText == null) {
      return FfmAppPinOperation.inactive;
    }
    try {
      final salt = base64Decode(saltText);
      final expectedHash = base64Decode(hashText);
      final candidateHash = _pbkdf2Sha256(pin, salt);
      return _constantTimeEquals(expectedHash, candidateHash)
          ? FfmAppPinOperation.success
          : FfmAppPinOperation.incorrectPin;
    } on FormatException {
      return FfmAppPinOperation.inactive;
    }
  }

  Future<FfmAppPinOperation> changePin({
    required String currentPin,
    required String nextPin,
  }) async {
    final verification = await verifyPin(currentPin);
    if (verification != FfmAppPinOperation.success) return verification;
    return createPin(nextPin);
  }

  Future<FfmAppPinOperation> disablePin(String currentPin) async {
    final verification = await verifyPin(currentPin);
    if (verification != FfmAppPinOperation.success) return verification;
    await _storage.delete(_schemaKey);
    await _storage.delete(_saltKey);
    await _storage.delete(_hashKey);
    await _storage.delete(_lengthKey);
    await _storage.delete(_legacyPinKey);
    return FfmAppPinOperation.success;
  }

  Uint8List _pbkdf2Sha256(String pin, List<int> salt) {
    final password = utf8.encode(pin);
    final result = BytesBuilder(copy: false);
    final blockCount = (_hashLength / sha256.convert(<int>[]).bytes.length)
        .ceil();
    for (var block = 1; block <= blockCount; block++) {
      var previous = _hmac(password, <int>[...salt, ..._int32(block)]);
      final output = Uint8List.fromList(previous);
      for (var iteration = 1; iteration < iterations; iteration++) {
        previous = _hmac(password, previous);
        for (var index = 0; index < output.length; index++) {
          output[index] ^= previous[index];
        }
      }
      result.add(output);
    }
    return Uint8List.fromList(result.takeBytes().sublist(0, _hashLength));
  }

  List<int> _hmac(List<int> key, List<int> value) =>
      Hmac(sha256, key).convert(value).bytes;

  List<int> _int32(int value) => <int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
