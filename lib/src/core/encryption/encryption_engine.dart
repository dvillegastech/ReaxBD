import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'encryption_type.dart';

import 'package:pointycastle/export.dart'
    if (dart.library.js_interop) 'encryption_wasm_fallback.dart';

bool get _isWasmRuntime =>
    identical(0, 0.0) || const bool.fromEnvironment('dart.library.js_interop');

/// High-performance encryption engine supporting multiple algorithms.
///
/// Provides XOR and AES-256-GCM encryption with optimized implementations
/// for different runtime environments.
class EncryptionEngine {
  final EncryptionType _type;
  final String? _key;

  Uint8List? _expandedXorKey;
  Uint8List? _aesKey;

  GCMBlockCipher? _gcmCipher;

  /// Creates an encryption engine with the specified type and key.
  ///
  /// [type] specifies the encryption algorithm to use.
  /// [key] is required for encryption types that need a key.
  EncryptionEngine({required EncryptionType type, String? key})
    : _type = type,
      _key = key {
    if (_type.requiresKey && (key == null || key.isEmpty)) {
      throw ArgumentError(
        'Encryption key is required for ${_type.displayName}',
      );
    }

    if (_type == EncryptionType.aes256 && _isWasmRuntime) {
      print(
        'Warning: Running in WASM mode. AES-256 using fallback implementation with reduced security.',
      );
    }

    if (_type == EncryptionType.xor && _key != null) {
      _expandedXorKey = _expandXorKey(_key);
    } else if (_type == EncryptionType.aes256 && _key != null) {
      _aesKey = _deriveAesKey(_key);
      _initializeAesGcm();
    }
  }

  /// Encrypts the provided data using the configured algorithm.
  Uint8List encrypt(Uint8List data) {
    if (_type == EncryptionType.none) return data;

    switch (_type) {
      case EncryptionType.none:
        return data;
      case EncryptionType.xor:
        return _encryptXor(data);
      case EncryptionType.aes256:
        return _encryptAes256(data);
    }
  }

  /// Decrypts the provided data using the configured algorithm.
  Uint8List decrypt(Uint8List data) {
    if (_type == EncryptionType.none) return data;

    switch (_type) {
      case EncryptionType.none:
        return data;
      case EncryptionType.xor:
        return _decryptXor(data);
      case EncryptionType.aes256:
        return _decryptAes256(data);
    }
  }

  /// Returns metadata about the encryption configuration.
  Map<String, dynamic> getMetadata() {
    return {
      'enabled': _type != EncryptionType.none,
      'type': _type.name,
      'display_name': _type.displayName,
      'security_level': _type.securityLevel,
      'performance_impact': _type.performanceImpact,
      'version': '1.0',
      'runtime': _isWasmRuntime ? 'wasm' : 'native',
      'wasm_fallback': _isWasmRuntime && _type == EncryptionType.aes256,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Uint8List _encryptXor(Uint8List data) {
    final key = _expandedXorKey!;
    final encrypted = Uint8List(data.length);
    final keyLen = key.length;

    int i = 0;
    for (; i + 16 <= data.length; i += 16) {
      encrypted[i] = data[i] ^ key[i % keyLen];
      encrypted[i + 1] = data[i + 1] ^ key[(i + 1) % keyLen];
      encrypted[i + 2] = data[i + 2] ^ key[(i + 2) % keyLen];
      encrypted[i + 3] = data[i + 3] ^ key[(i + 3) % keyLen];
      encrypted[i + 4] = data[i + 4] ^ key[(i + 4) % keyLen];
      encrypted[i + 5] = data[i + 5] ^ key[(i + 5) % keyLen];
      encrypted[i + 6] = data[i + 6] ^ key[(i + 6) % keyLen];
      encrypted[i + 7] = data[i + 7] ^ key[(i + 7) % keyLen];
      encrypted[i + 8] = data[i + 8] ^ key[(i + 8) % keyLen];
      encrypted[i + 9] = data[i + 9] ^ key[(i + 9) % keyLen];
      encrypted[i + 10] = data[i + 10] ^ key[(i + 10) % keyLen];
      encrypted[i + 11] = data[i + 11] ^ key[(i + 11) % keyLen];
      encrypted[i + 12] = data[i + 12] ^ key[(i + 12) % keyLen];
      encrypted[i + 13] = data[i + 13] ^ key[(i + 13) % keyLen];
      encrypted[i + 14] = data[i + 14] ^ key[(i + 14) % keyLen];
      encrypted[i + 15] = data[i + 15] ^ key[(i + 15) % keyLen];
    }

    for (; i < data.length; i++) {
      encrypted[i] = data[i] ^ key[i % keyLen];
    }

    return encrypted;
  }

  Uint8List _decryptXor(Uint8List data) {
    return _encryptXor(data);
  }

  Uint8List _encryptAes256(Uint8List data) {
    _gcmCipher ??= _createGcmCipher();

    final iv = _generateFastIV();

    final params = AEADParameters(
      KeyParameter(_aesKey!),
      128,
      iv,
      Uint8List(0),
    );
    _gcmCipher!.init(true, params);

    final encrypted = _gcmCipher!.process(data);

    final result =
        Uint8List(12 + encrypted.length)
          ..setRange(0, 12, iv)
          ..setRange(12, 12 + encrypted.length, encrypted);

    return result;
  }

  Uint8List _decryptAes256(Uint8List data) {
    if (data.length < 12) {
      throw ArgumentError('Invalid encrypted data: too short');
    }

    _gcmCipher ??= _createGcmCipher();

    final iv = Uint8List.view(data.buffer, 0, 12);
    final encrypted = Uint8List.view(data.buffer, 12);

    final params = AEADParameters(
      KeyParameter(_aesKey!),
      128,
      iv,
      Uint8List(0),
    );
    _gcmCipher!.init(false, params);

    return _gcmCipher!.process(encrypted);
  }

  void _initializeAesGcm() {
    _gcmCipher = _createGcmCipher();
  }

  GCMBlockCipher _createGcmCipher() {
    final aes = AESEngine();
    return GCMBlockCipher(aes);
  }

  int _ivCounter = 0;
  Uint8List _generateFastIV() {
    final iv = Uint8List(12);
    final counter = ++_ivCounter;

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 8; i++) {
      iv[i] = (timestamp >> (i * 8)) & 0xFF;
    }
    for (int i = 0; i < 4; i++) {
      iv[8 + i] = (counter >> (i * 8)) & 0xFF;
    }

    return iv;
  }

  Uint8List _expandXorKey(String key) {
    final keyBytes = Uint8List.fromList(key.codeUnits);
    const expandedLength = 512;
    final expanded = Uint8List(expandedLength);

    final keyLen = keyBytes.length;
    for (int i = 0; i < expandedLength; i++) {
      expanded[i] = keyBytes[i % keyLen];
    }

    return expanded;
  }

  Uint8List _deriveAesKey(String password) {
    final salt = utf8.encode('ReaxDB_Salt_v1_2025');
    final combined = utf8.encode(password) + salt;

    var hash = sha256.convert(combined).bytes;
    for (int i = 0; i < 10000; i++) {
      hash = sha256.convert(hash).bytes;
    }

    return Uint8List.fromList(hash);
  }
}
