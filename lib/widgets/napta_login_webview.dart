import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'glass_container.dart';

class NaptaLoginWebView extends StatefulWidget {
  final String? initialEmail;
  final String? initialPassword;

  const NaptaLoginWebView({super.key, this.initialEmail, this.initialPassword});

  @override
  State<NaptaLoginWebView> createState() => _NaptaLoginWebViewState();
}

class _NaptaLoginWebViewState extends State<NaptaLoginWebView> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;

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
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri("https://app.napta.io/login"),
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    onLoadStart: (controller, url) {
                      setState(() => _isLoading = true);
                    },
                    onLoadStop: (controller, url) async {
                      setState(() => _isLoading = false);
                      if (url != null && url.toString().contains('/login')) {
                        _autoFill();
                      }
                      _checkForCookie();
                    },
                    onConsoleMessage: (controller, consoleMessage) {
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

  Future<void> _autoFill() async {
    if (_webViewController == null) return;
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
              console.log("[AutoFill] Step 1: Filling Email");
              emailInput.value = $emailJson;
              emailInput.dispatchEvent(new Event('input', { bubbles: true }));
              
              var nextBtn = document.getElementsByClassName('napta-button')[0];
              if (nextBtn && nextBtn.offsetParent !== null) {
                console.log("[AutoFill] Clicking Next");
                hasClicked = true;
                nextBtn.click();
              }
            } 
            // Step 2: Password Screen (Check if visible)
            else if (passwordInput && passwordInput.offsetParent !== null) {
              console.log("[AutoFill] Step 2: Filling Password");
              passwordInput.value = $passwordJson;
              passwordInput.dispatchEvent(new Event('input', { bubbles: true }));
              
              var loginBtn = document.getElementsByClassName('_button-login-password')[0];
              if (loginBtn && loginBtn.offsetParent !== null) {
                console.log("[AutoFill] Clicking Login");
                hasClicked = true;
                loginBtn.click();
              }
            }
          } catch (e) {
            console.error("[AutoFill] Error during step execution:", e);
          }
        }

        runStep();
        setTimeout(runStep, 500);
        setTimeout(runStep, 1500);
      })();
    """;

    await _webViewController!.evaluateJavascript(source: js);
  }

  Future<void> _checkForCookie() async {
    if (_webViewController == null) return;

    CookieManager cookieManager = CookieManager.instance();
    final cookie = await cookieManager.getCookie(
      url: WebUri("https://app.napta.io"),
      name: "naptaSession",
    );

    if (cookie != null && cookie.value != null) {
      if (mounted) {
        Navigator.of(context).pop(cookie.value.toString());
      }
    }
  }
}
