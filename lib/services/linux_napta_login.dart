import 'dart:async';
import 'dart:convert';

import 'package:desktop_webview_window/desktop_webview_window.dart';

/// Napta login on Linux, where flutter_inappwebview isn't available: opens the
/// Napta login page in a native WebKitGTK window, auto-fills the credentials
/// and returns the `naptaSession` cookie once the user is logged in.
class LinuxNaptaLogin {
  static const _loginUrl = 'https://app.napta.io/login';
  static const _cookieName = 'naptaSession';

  /// Returns the session cookie, or null if the user closed the window.
  /// Throws when no webview can be created (the caller falls back to the
  /// manual cookie entry).
  static Future<String?> login({String? email, String? password}) async {
    if (!await WebviewWindow.isWebviewAvailable()) {
      throw StateError('WebKitGTK webview unavailable');
    }
    // Start from a clean session, like the macOS login does.
    await WebviewWindow.clearAll();

    final webview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        windowWidth: 600,
        windowHeight: 760,
        title: 'Connexion Napta',
        // No Flutter title bar: it would need a second engine in main().
        titleBarHeight: 0,
      ),
    );

    final result = Completer<String?>();
    webview.onClose.then((_) {
      if (!result.isCompleted) result.complete(null);
    });
    webview.launch(_loginUrl);

    // Each step is auto-filled once: retrying the password after a failed
    // login could lock the account.
    var emailFilled = false;
    var passwordFilled = false;
    var polling = false;

    final timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (polling || result.isCompleted) return;
      polling = true;
      try {
        final cookies = await webview.getAllCookies();
        final session = cookies
            .where((c) => c.name == _cookieName && c.value.isNotEmpty)
            .firstOrNull;
        if (session != null) {
          if (!result.isCompleted) result.complete(session.value);
          webview.close();
          return;
        }

        if (email != null &&
            password != null &&
            !(emailFilled && passwordFilled)) {
          final step = await webview.evaluateJavaScript(
            _autofillScript(
              email: email,
              password: password,
              fillEmail: !emailFilled,
              fillPassword: !passwordFilled,
            ),
          );
          // WebKitGTK returns the JS string JSON-encoded.
          if (step != null && step.contains('email')) emailFilled = true;
          if (step != null && step.contains('password')) passwordFilled = true;
        }
      } catch (_) {
        // Page still loading or window closing: try again on the next tick.
      } finally {
        polling = false;
      }
    });

    try {
      return await result.future;
    } finally {
      timer.cancel();
    }
  }

  /// Fills the visible step of the Napta/Keycloak login form and submits it.
  /// Returns which step was filled ("email", "password" or "").
  static String _autofillScript({
    required String email,
    required String password,
    required bool fillEmail,
    required bool fillPassword,
  }) {
    return '''
      (function() {
        var emailInput = document.getElementById('email');
        var passwordInput = document.getElementById('password');
        var visible = function(el) { return el && el.offsetParent !== null; };

        if ($fillEmail && visible(emailInput) && !passwordInput) {
          var nextBtn = document.getElementsByClassName('napta-button')[0];
          if (!visible(nextBtn)) return '';
          emailInput.value = ${jsonEncode(email)};
          emailInput.dispatchEvent(new Event('input', { bubbles: true }));
          nextBtn.click();
          return 'email';
        }
        if ($fillPassword && visible(passwordInput)) {
          var loginBtn = document.getElementById('kc-login');
          if (!visible(loginBtn)) return '';
          passwordInput.value = ${jsonEncode(password)};
          passwordInput.dispatchEvent(new Event('input', { bubbles: true }));
          loginBtn.click();
          return 'password';
        }
        return '';
      })();
    ''';
  }
}
