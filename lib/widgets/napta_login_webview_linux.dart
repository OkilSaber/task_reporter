import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'glass_container.dart';

/// Linux-specific webview login for Napta, using webview_flutter v3 +
/// flutter_linux_webview (CEF-based).  Mirrors the behaviour of
/// [NaptaLoginWebView] (used on macOS / Windows) but targets the
/// webview_flutter API surface available on Linux.
class NaptaLoginWebViewLinux extends StatefulWidget {
  final String? initialEmail;
  final String? initialPassword;

  const NaptaLoginWebViewLinux({
    super.key,
    this.initialEmail,
    this.initialPassword,
  });

  @override
  State<NaptaLoginWebViewLinux> createState() => _NaptaLoginWebViewLinuxState();
}

class _NaptaLoginWebViewLinuxState extends State<NaptaLoginWebViewLinux> {
  WebViewController? _controller;
  bool _isLoading = true;
  Timer? _cookiePoller;

  @override
  void dispose() {
    _cookiePoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 600,
          height: 700,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.security_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Task Reporter Login',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    if (_isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                  child: WebView(
                    initialUrl: 'https://app.napta.io/login',
                    javascriptMode: JavascriptMode.unrestricted,
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onPageStarted: (_) {
                      if (mounted) setState(() => _isLoading = true);
                    },
                    onPageFinished: (url) {
                      if (mounted) setState(() => _isLoading = false);
                      if (url.contains('/login')) {
                        _autoFill();
                      }
                      _startCookiePolling();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Auto-fill email / password fields using injected JS, same logic as
  /// the macOS/Windows [NaptaLoginWebView].
  Future<void> _autoFill() async {
    if (_controller == null) return;
    if (widget.initialEmail == null || widget.initialPassword == null) return;

    final emailJson = jsonEncode(widget.initialEmail);
    final passwordJson = jsonEncode(widget.initialPassword);

    final js = """
      (function() {
        var hasClicked = false;

        function runStep() {
          if (hasClicked) return;
          
          try {
            var emailInput = document.getElementById('email');
            var passwordInput = document.getElementById('password');

            // Step 1: Email Screen (Check if visible)
            if (emailInput && emailInput.offsetParent !== null && !passwordInput) {
              emailInput.value = $emailJson;
              emailInput.dispatchEvent(new Event('input', { bubbles: true }));
              
              var nextBtn = document.getElementsByClassName('napta-button')[0];
              if (nextBtn && nextBtn.offsetParent !== null) {
                hasClicked = true;
                nextBtn.click();
              }
            } 
            // Step 2: Password Screen (Check if visible)
            else if (passwordInput && passwordInput.offsetParent !== null) {
              passwordInput.value = $passwordJson;
              passwordInput.dispatchEvent(new Event('input', { bubbles: true }));
              
              var loginBtn = document.getElementsByClassName('_button-login-password')[0];
              if (loginBtn && loginBtn.offsetParent !== null) {
                hasClicked = true;
                loginBtn.click();
              }
            }
          } catch (e) {
            console.error("[AutoFill] Error:", e);
          }
        }

        runStep();
        setTimeout(runStep, 500);
        setTimeout(runStep, 1500);
      })();
    """;

    await _controller!.runJavascript(js);
  }

  /// Since flutter_linux_webview doesn't expose a native CookieManager,
  /// we poll `document.cookie` via JS to detect the `naptaSession` cookie.
  void _startCookiePolling() {
    _cookiePoller?.cancel();
    _cookiePoller = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _checkForCookie();
    });
  }

  Future<void> _checkForCookie() async {
    if (_controller == null) return;

    try {
      // evaluateJavascript returns the result as a string (possibly quoted)
      final raw = await _controller!.runJavascriptReturningResult(
        'document.cookie',
      );

      // The returned value is JSON-encoded (wrapped in quotes)
      String cookies = raw;
      if (cookies.startsWith('"') && cookies.endsWith('"')) {
        cookies = cookies.substring(1, cookies.length - 1);
      }

      // Parse the cookie string to find naptaSession
      final parts = cookies.split(';');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.startsWith('naptaSession=')) {
          final value = trimmed.substring('naptaSession='.length);
          if (value.isNotEmpty && mounted) {
            _cookiePoller?.cancel();
            Navigator.of(context).pop(value);
            return;
          }
        }
      }
    } catch (_) {
      // JS execution may fail during navigation — ignore and retry
    }
  }
}
