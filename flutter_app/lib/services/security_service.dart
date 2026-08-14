import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../utils/constants.dart';

/// PIN + biometric gate. The PIN is never stored in plaintext.
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _auth = LocalAuthentication();

  Future<bool> hasPin() async =>
      (await _secure.read(key: SecureKeys.pinHash)) != null;

  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    await _secure.write(key: SecureKeys.pinSalt, value: salt);
    await _secure.write(key: SecureKeys.pinHash, value: _hash(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _secure.read(key: SecureKeys.pinSalt);
    final hash = await _secure.read(key: SecureKeys.pinHash);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<void> clearPin() async {
    await _secure.delete(key: SecureKeys.pinHash);
    await _secure.delete(key: SecureKeys.pinSalt);
  }

  Future<bool> biometricAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric({
    String reason = 'Unlock your document wallet',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt::$pin')).toString();

  String _randomSalt() {
    final rnd = Random.secure();
    return base64Url.encode(List<int>.generate(24, (_) => rnd.nextInt(256)));
  }
}
