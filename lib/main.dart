import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_linux_webview/flutter_linux_webview.dart';
import 'services/secure_prefs.dart';
import 'home_page.dart';
import 'screens/login_screen.dart';
import 'services/napta_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr', null);

  if (Platform.isLinux) {
    debugPrint('Linux detected');
    await LinuxWebViewPlugin.initialize(options: <String, String?>{
      'no-sandbox': null,
    });
    debugPrint('Linux WebView initialized');
    WebView.platform = LinuxWebView();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Reporter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'SF Pro Display',
      ),
      home: const _SplashRouter(),
    );
  }
}

/// Checks for a stored session cookie on startup and routes accordingly.
class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _route();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (Platform.isLinux) {
      await LinuxWebViewPlugin.terminate();
    }
    return AppExitResponse.exit;
  }

  Future<void> _route() async {
    final session = await SecurePrefs.read('naptaSession');

    if (!mounted) return;

    if (session != null && session.isNotEmpty) {
      // Try to validate the stored session
      try {
        final service = NaptaService(sessionCookie: session);
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
        } else {}
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
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  HomePage(naptaSession: session, naptaUser: userDetails),
            ),
          );
        }
      } catch (_) {
        // Session expired — go to login
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  static Future<void> _saveProjectsAsCategories(
    List<Map<String, dynamic>> projects,
  ) async {
    const palette = [
      0xFF4FC3F7,
      0xFF81C784,
      0xFFFFD54F,
      0xFFD32F2F,
      0xFFBA68C8,
      0xFF26A69A,
      0xFFAD1457,
      0xFF1976D2,
      0xFF7E57C2,
      0xFF388E3C,
      0xFF5D4037,
      0xFF263238,
    ];
    final prefs = await SharedPreferences.getInstance();
    final existing =
        jsonDecode(prefs.getString('categoriesData') ?? '[]') as List<dynamic>;
    final existingIds = existing.map((c) => c['id'] as String).toSet();
    for (final p in projects) {
      final id = 'napta_${p['id']}';
      if (existingIds.contains(id)) continue;
      final prefix = p['client_name'] != null ? '${p['client_name']} – ' : '';
      existing.add({
        'id': id,
        'name': '$prefix${p['name']}',
        'color': palette[existing.length % palette.length],
      });
    }
    await prefs.setString('categoriesData', jsonEncode(existing));
  }

  static Future<void> _mergeLockedCategories(
    Map<String, Map<String, double>> dayRecords,
  ) async {
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
    // Splash loading screen
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243e)],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
