import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurePrefs {
  static const _secure = FlutterSecureStorage();

  /// Writes a value to secure storage. Falls back to standard SharedPreferences on error.
  static Future<void> write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } catch (_) {}
    }
  }

  /// Reads a value from secure storage. Falls back to reading from SharedPreferences if missing or on error.
  static Future<String?> read(String key) async {
    try {
      final value = await _secure.read(key: key);
      if (value != null) return value;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// Deletes a value from both secure storage and SharedPreferences.
  static Future<void> delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}
