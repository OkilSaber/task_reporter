import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/secure_prefs.dart';
import 'home_page.dart';
import 'screens/login_screen.dart';
import 'services/napta_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr', null);
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

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate cleartext credentials to secure storage if they exist
    if (prefs.containsKey('naptaSession')) {
      final oldSession = prefs.getString('naptaSession');
      if (oldSession != null) {
        await SecurePrefs.write('naptaSession', oldSession);
      }
      await prefs.remove('naptaSession');
    }
    if (prefs.containsKey('napta_email')) {
      final oldEmail = prefs.getString('napta_email');
      if (oldEmail != null) {
        await SecurePrefs.write('napta_email', oldEmail);
      }
      await prefs.remove('napta_email');
    }
    if (prefs.containsKey('napta_password')) {
      final oldPassword = prefs.getString('napta_password');
      if (oldPassword != null) {
        await SecurePrefs.write('napta_password', oldPassword);
      }
      await prefs.remove('napta_password');
    }

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
      0xFFFFB74D,
      0xFFE57373,
      0xFFBA68C8,
      0xFF4DB6AC,
      0xFFF06292,
      0xFFFFD54F,
      0xFF64B5F6,
      0xFFA5D6A7,
      0xFFFF8A65,
      0xFF90A4AE,
    ];
    final categories = projects.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final prefix = p['client_name'] != null ? '${p['client_name']} – ' : '';
      return {
        'id': 'napta_${p['id']}',
        'name': '$prefix${p['name']}',
        'color': palette[i % palette.length],
      };
    }).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('categoriesData', jsonEncode(categories));
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
