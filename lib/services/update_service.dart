import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class UpdateService {
  static const String currentVersion = '1.3.0';
  static const String _releasesUrl =
      'https://api.github.com/repos/OkilSaber/task_reporter/releases/latest';

  /// Compares two version strings (e.g., '1.0.2' and '1.0.1').
  /// Returns 1 if v1 > v2, -1 if v1 < v2, and 0 if they are equal.
  static int compareVersions(String v1, String v2) {
    v1 = v1.replaceAll(RegExp(r'^v'), '').trim();
    v2 = v2.replaceAll(RegExp(r'^v'), '').trim();

    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final length = parts1.length > parts2.length
        ? parts1.length
        : parts2.length;
    for (int i = 0; i < length; i++) {
      final val1 = i < parts1.length ? parts1[i] : 0;
      final val2 = i < parts2.length ? parts2[i] : 0;
      if (val1 < val2) return -1;
      if (val1 > val2) return 1;
    }
    return 0;
  }

  /// Checks if a new release is available on GitHub.
  /// Returns a Map with update details if available, or null otherwise.
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_releasesUrl),
        headers: {
          'accept': 'application/vnd.github.v3+json',
          'user-agent': 'task-reporter-updater',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestVersion = (data['tag_name'] ?? '').toString();

        if (latestVersion.isNotEmpty) {
          if (compareVersions(latestVersion, currentVersion) > 0) {
            // Find download link (e.g. DMG asset or release HTML URL)
            String? downloadUrl;
            if (!Platform.isLinux) {
              final assets = data['assets'] as List<dynamic>? ?? [];
              for (final asset in assets) {
                final name = (asset['name'] ?? '').toString();
                if (name.endsWith('.dmg')) {
                  downloadUrl = (asset['browser_download_url'] ?? '')
                      .toString();
                  break;
                }
              }
            }
            // On Linux (or if no matching asset is found), open the release page
            downloadUrl ??= (data['html_url'] ?? '').toString();

            return {
              'version': latestVersion,
              'title': (data['name'] ?? 'Mise à jour disponible').toString(),
              'body': (data['body'] ?? '').toString(),
              'downloadUrl': downloadUrl,
            };
          }
        }
      }
    } catch (_) {
      // Ignore network / update check errors
    }
    return null;
  }

  /// Opens the download URL in the default browser.
  static Future<void> launchDownload(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // Ignore launch errors
    }
  }
}
