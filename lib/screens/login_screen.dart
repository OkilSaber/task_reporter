import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/napta_service.dart';
import '../widgets/glass_container.dart';
import '../widgets/napta_login_webview.dart';
import '../widgets/linux_cookie_dialog.dart';
import '../services/secure_prefs.dart';
import '../home_page.dart';
import 'dart:io';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final email = await SecurePrefs.read('napta_email');
    final password = await SecurePrefs.read('napta_password');
    if (email != null) _emailController.text = email;
    if (password != null) _passwordController.text = password;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Veuillez saisir votre email et mot de passe.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Save credentials in secure storage
    await SecurePrefs.write('napta_email', email);
    await SecurePrefs.write('napta_password', password);

    final String? cookie;
    if (Platform.isLinux) {
      if (!mounted) return;
      cookie = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const LinuxCookieDialog(),
      );
    } else {
      if (!mounted) return;
      cookie = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => NaptaLoginWebView(
          initialEmail: email,
          initialPassword: password,
        ),
      );
    }

    if (cookie == null || cookie.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connexion annulée ou impossible.';
      });
      return;
    }

    try {
      final service = NaptaService(sessionCookie: cookie);
      // ... rest of the existing logic ...
      final whoAmI = await service.whoAmI();
      // whoAmI gives us the user ID; fetch the full profile
      final userId = (whoAmI['userId'] ?? '').toString();
      Map<String, dynamic> userDetails = whoAmI;
      if (userId.isNotEmpty && userId != 'null') {
        try {
          userDetails = await service.getUserDetails(userId);
        } catch (e) {
          // Error ignored
        }
      } else {
      }

      // Fetch user's Napta projects and save as categories
      if (userId.isNotEmpty && userId != 'null') {
        try {
          final projects = await service.getUserProjects(userId);
          await _saveProjectsAsCategories(projects);
        } catch (e) {
          // Error ignored
        }
        // Prefill day records from current and previous month's reporting
        try {
          final now = DateTime.now();
          final prev = DateTime(now.year, now.month - 1, 1);

          final currentData = await service.getMonthlyDayRecords(
            userId,
            year: now.year,
            month: now.month,
          );
          final prevData = await service.getMonthlyDayRecords(
            userId,
            year: prev.year,
            month: prev.month,
          );

          final dayRecords = {...prevData.records, ...currentData.records};
          final statuses = {...prevData.statuses, ...currentData.statuses};

          final prefs2 = await SharedPreferences.getInstance();
          await prefs2.setString('dayRecordsData', jsonEncode(dayRecords));
          await prefs2.setString('dayStatusesData', jsonEncode(statuses));
          await _mergeLockedCategories(dayRecords);
        } catch (e) {
          // Error ignored
        }
      }

      await SecurePrefs.write('naptaSession', cookie);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(naptaSession: cookie, naptaUser: userDetails),
          ),
        );
      }
    } on NaptaAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } on NaptaException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Convert a list of Napta projects to Category JSON and persist to cache.
  static Future<void> _saveProjectsAsCategories(
      List<Map<String, dynamic>> projects) async {
    // A palette of visually distinct, vibrant colors
    const palette = [
      0xFF4FC3F7, // light blue
      0xFF81C784, // green
      0xFFFFB74D, // orange
      0xFFE57373, // red
      0xFFBA68C8, // purple
      0xFF4DB6AC, // teal
      0xFFF06292, // pink
      0xFFFFD54F, // amber
      0xFF64B5F6, // blue
      0xFFA5D6A7, // light green
      0xFFFF8A65, // deep orange
      0xFF90A4AE, // blue grey
    ];

    final categories = projects.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final clientPrefix =
          p['client_name'] != null ? '${p['client_name']} – ' : '';
      return {
        'id': 'napta_${p['id']}',
        'name': '$clientPrefix${p['name']}',
        'color': palette[i % palette.length],
      };
    }).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('categoriesData', jsonEncode(categories));
  }

  static Future<void> _mergeLockedCategories(
      Map<String, Map<String, double>> dayRecords) async {
    final locked = NaptaService.buildLockedCategories(dayRecords);
    if (locked.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing =
        jsonDecode(prefs.getString('categoriesData') ?? '[]') as List<dynamic>;
    final existingIds = existing.map((c) => c['id'] as String).toSet();
    for (final cat in locked) {
      if (!existingIds.contains(cat['id'])) existing.add(cat);
    }
    await prefs.setString('categoriesData', jsonEncode(existing));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F0C29),
                  Color(0xFF302B63),
                  Color(0xFF24243e),
                ],
              ),
            ),
          ),
          // Blobs
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purpleAccent.withValues(alpha: 0.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purpleAccent.withValues(alpha: 0.3),
                    blurRadius: 120,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                    blurRadius: 120,
                  ),
                ],
              ),
            ),
          ),
          // Main card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  padding: const EdgeInsets.all(40),
                  borderRadius: BorderRadius.circular(32),
                  child: SizedBox(
                    width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo / title
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/logo.svg',
                            width: 48,
                            height: 48,
                          ),
                          const SizedBox(width: 16),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Task Reporter',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Assistant de Reporting',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'Identifiants Napta',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassContainer(
                        opacity: 0.08,
                        blur: 0,
                        borderRadius: BorderRadius.circular(16),
                        child: TextField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            prefixIcon: Icon(Icons.email_outlined, color: Colors.white38, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassContainer(
                        opacity: 0.08,
                        blur: 0,
                        borderRadius: BorderRadius.circular(16),
                        child: TextField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'Mot de passe',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            prefixIcon: Icon(Icons.lock_outline, color: Colors.white38, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Help text
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.white38, size: 14),
                          const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Vos identifiants sont enregistrés localement pour faciliter vos prochaines connexions.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _isLoading ? null : _connect,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}
