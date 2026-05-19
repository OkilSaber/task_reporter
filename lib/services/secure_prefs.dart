import 'dart:convert';

import 'package:encrypt/encrypt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Obfuscated credential storage on top of [SharedPreferences].
///
/// AES-CBC with a per-install 256-bit key generated on first launch and
/// stored alongside the ciphertext in SharedPreferences. This prevents
/// credentials from appearing in cleartext in the preferences file, but
/// it is not real security: anyone with read access to the same file can
/// also read the key. The wrapper exists because the macOS Keychain path
/// requires a properly signed/notarized build, which this app does not
/// currently produce.
class SecurePrefs {
  static const _masterKeyPref = '_sp_master_key';
  static Encrypter? _encrypter;

  static Future<Encrypter> _enc() async {
    final cached = _encrypter;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var b64 = prefs.getString(_masterKeyPref);
    if (b64 == null) {
      b64 = Key.fromSecureRandom(32).base64;
      await prefs.setString(_masterKeyPref, b64);
    }
    final encrypter = Encrypter(AES(Key.fromBase64(b64)));
    _encrypter = encrypter;
    return encrypter;
  }

  static Future<void> write(String key, String value) async {
    final encrypter = await _enc();
    final iv = IV.fromSecureRandom(16);
    final ciphertext = encrypter.encrypt(value, iv: iv);
    final blob = base64Encode([...iv.bytes, ...ciphertext.bytes]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, blob);
  }

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString(key);
    if (blob == null) return null;
    try {
      final bytes = base64Decode(blob);
      if (bytes.length <= 16) return null;
      final iv = IV(bytes.sublist(0, 16));
      final ciphertext = Encrypted(bytes.sublist(16));
      final encrypter = await _enc();
      return encrypter.decrypt(ciphertext, iv: iv);
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
