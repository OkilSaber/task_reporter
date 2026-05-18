import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/category.dart';
import 'screens/login_screen.dart';
import 'services/napta_service.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/category_manager_dialog.dart';
import 'widgets/glass_container.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';

class HomePage extends StatefulWidget {
  final String? naptaSession;
  final Map<String, dynamic>? naptaUser;

  const HomePage({super.key, this.naptaSession, this.naptaUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime _currentMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  List<Category> _categories = [
    Category(id: 'default', name: 'Défaut', color: Colors.greenAccent),
  ];
  Map<String, Map<String, double>> _dayRecords = {}; // dateStr -> catId -> val
  Map<String, String> _dayStatuses = {}; // dateStr -> status
  final Map<String, String> _dayComments = {}; // dateStr -> comment
  bool _isSyncing = false;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  final Set<String> _fetchedMonths = {}; // 'yyyy-MM' keys already fetched
  final Set<String> _modifiedDates = {}; // track days changed but not yet saved to Napta

  late SharedPreferences _prefs;
  Timer? _todayTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startTodayTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdates();
    });
  }

  @override
  void dispose() {
    _todayTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkUpdates() async {
    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => UpdateDialog(updateInfo: updateInfo),
      );
    }
  }

  void _startTodayTimer() {
    // Rebuild the UI every minute to ensure the "today" indicator updates if midnight passes
    _todayTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();

    // Load categories
    final catsData = _prefs.getString('categoriesData');
    if (catsData != null) {
      final List<dynamic> decodedCats = jsonDecode(catsData);
      _categories = decodedCats.map((c) => Category.fromJson(c)).toList();
    }

    // Load records
    final data = _prefs.getString('dayRecordsData');
    if (data != null) {
      final Map<String, dynamic> decoded = jsonDecode(data);
      final Map<String, Map<String, double>> parsed = {};
      decoded.forEach((dateStr, dayMap) {
        parsed[dateStr] = (dayMap as Map<String, dynamic>).map(
          (catId, val) => MapEntry(catId, (val as num).toDouble()),
        );
      });
      setState(() {
        _dayRecords = parsed;
        // Mark the startup month as already loaded from cache
        _fetchedMonths.clear();
        final monthKey =
            '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';
        _fetchedMonths.add(monthKey);
      });
    }

    // Load statuses
    final statusesData = _prefs.getString('dayStatusesData');
    if (statusesData != null) {
      final Map<String, dynamic> decoded = jsonDecode(statusesData);
      setState(() {
        _dayStatuses = decoded.cast<String, String>();
      });
    } else {
      // Data Migration from old format:
      final oldData = _prefs.getString('manDaysData');
      if (oldData != null) {
        final Map<String, dynamic> decoded = jsonDecode(oldData);
        final Map<String, Map<String, double>> parsed = {};
        decoded.forEach((dateStr, val) {
          parsed[dateStr] = {'default': (val as num).toDouble()};
        });
        setState(() {
          _dayRecords = parsed;
        });
        _saveData();
      }
    }

    // Load comments
    final commentsData = _prefs.getString('dayCommentsData');
    if (commentsData != null) {
      final Map<String, dynamic> decoded = jsonDecode(commentsData);
      setState(() {
        _dayComments.clear();
        _dayComments.addAll(decoded.cast<String, String>());
      });
    }
  }

  Future<void> _saveData() async {
    // Save categories
    final catsJson = jsonEncode(_categories.map((c) => c.toJson()).toList());
    await _prefs.setString('categoriesData', catsJson);

    // Save records
    final recordsJson = jsonEncode(_dayRecords);
    await _prefs.setString('dayRecordsData', recordsJson);

    // Save statuses
    final statusesJson = jsonEncode(_dayStatuses);
    await _prefs.setString('dayStatusesData', statusesJson);

    // Save comments
    final commentsJson = jsonEncode(_dayComments);
    await _prefs.setString('dayCommentsData', commentsJson);
  }

  void _onDayDataChanged(
    DateTime date,
    Map<String, double> newRecords,
    String newComment,
  ) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    setState(() {
      _dayRecords[dateStr] = newRecords;
      if (newComment.trim().isEmpty) {
        _dayComments.remove(dateStr);
      } else {
        _dayComments[dateStr] = newComment;
      }
      _dayStatuses[dateStr] = 'saved'; // Reset to saved so submit reappears
      _hasUnsavedChanges = true;
      _modifiedDates.add(dateStr);
    });
    _saveData();
  }

  void _openCategoryManager() {
    final session = widget.naptaSession;
    if (session == null) return;
    final service = NaptaService(sessionCookie: session);

    showDialog(
      context: context,
      builder: (context) {
        return CategoryManagerDialog(
          categories: _categories,
          naptaService: service,
          onCategoriesChanged: (newCats) {
            setState(() {
              _categories = newCats;
            });
            _saveData();
          },
        );
      },
    );
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    setState(() => _currentMonth = next);
    _fetchMonthIfNeeded(next);
  }

  void _prevMonth() {
    final prev = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    setState(() => _currentMonth = prev);
    _fetchMonthIfNeeded(prev);
  }

  void _goToToday() {
    final today = DateTime(DateTime.now().year, DateTime.now().month, 1);
    setState(() => _currentMonth = today);
    _fetchMonthIfNeeded(today);
  }

  /// Fetches reporting for [month] if not already cached, then merges
  /// the results into the existing _dayRecords map.
  Future<void> _fetchMonthIfNeeded(DateTime month) async {
    await _fetchSingleMonth(month);
    final prevMonth = DateTime(month.year, month.month - 1, 1);
    await _fetchSingleMonth(prevMonth);
  }

  Future<void> _fetchSingleMonth(DateTime month) async {
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    if (_fetchedMonths.contains(monthKey)) return;

    final session = widget.naptaSession;
    final userId = widget.naptaUser?['userId']?.toString();
    if (session == null || userId == null || userId == 'null') return;

    setState(() => _isSyncing = true);
    try {
      final service = NaptaService(sessionCookie: session);

      // Discover new projects for this specific month
      final projects = await service.getUserProjects(
        userId,
        year: month.year,
        month: month.month,
      );
      await _saveProjectsAsCategories(projects);

      final data = await service.getMonthlyDayRecords(
        userId,
        year: month.year,
        month: month.month,
      );

      // Merge — other months’ records stay intact
      setState(() {
        _dayRecords.addAll(data.records);
        _dayStatuses.addAll(data.statuses);
        _fetchedMonths.add(monthKey);
      });

      // Persist merged data
      await _prefs.setString('dayRecordsData', jsonEncode(_dayRecords));
      await _prefs.setString('dayStatusesData', jsonEncode(_dayStatuses));

      // Merge any new locked holiday categories
      await _mergeLockedCategories(data.records);

      // Reload categories in case new locked cats were added
      final catsData = _prefs.getString('categoriesData');
      if (catsData != null && mounted) {
        final decoded = jsonDecode(catsData) as List<dynamic>;
        setState(() {
          _categories = decoded.map((c) => Category.fromJson(c)).toList();
        });
      }
    } catch (e) {
      // Error ignored
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  double get _currentMonthTotal {
    double total = 0;
    // Exclude locked holiday categories from the JH total
    final lockedIds = _categories
        .where((c) => c.isLocked)
        .map((c) => c.id)
        .toSet();

    _dayRecords.forEach((key, dayMap) {
      final date = DateFormat('yyyy-MM-dd').parse(key);
      if (date.year == _currentMonth.year &&
          date.month == _currentMonth.month) {
        // Skip weekends as they are "off days"
        if (date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday) {
          return;
        }

        dayMap.forEach((catId, val) {
          // Skip locked holiday categories (bank holidays, congés)
          if (lockedIds.contains(catId)) return;

          // Double-check for Napta holiday IDs as a fallback
          if (catId == 'napta_bank_holiday' ||
              catId.startsWith('napta_holiday_')) {
            return;
          }

          total += val;
        });
      }
    });
    return total;
  }

  void _showUserInfo(BuildContext context) {
    final user = widget.naptaUser!;
    final fullName =
        '${user['first_name'] ?? user['firstname'] ?? ''} ${user['last_name'] ?? user['lastname'] ?? ''}'
            .trim();
    final email = user['email'] ?? '';
    final picture = user['picture'] as String?;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: GlassContainer(
            padding: const EdgeInsets.all(28),
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + name header
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          image: picture != null
                              ? DecorationImage(
                                  image: NetworkImage(picture),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: picture == null
                            ? const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 30,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName.isEmpty ? 'Utilisateur' : fullName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (email.isNotEmpty)
                              Text(
                                email,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white60,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (user['active'] == true)
                                  _chip('Actif', Colors.greenAccent),
                                if (user['is_vip'] == true) ...[
                                  const SizedBox(width: 6),
                                  _chip('VIP', Colors.amberAccent),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 12),
                  // Info grid
                  _infoRow(
                    Icons.work_outline_rounded,
                    'Poste',
                    user['position'],
                  ),
                  _infoRow(
                    Icons.business_rounded,
                    'Business Unit',
                    user['business_unit'],
                  ),
                  _infoRow(
                    Icons.location_on_outlined,
                    'Localisation',
                    user['location'] != null
                        ? '${user['location']} (${user['location_country'] ?? ''})'
                        : null,
                  ),
                  _infoRow(Icons.group_outlined, 'Groupe', user['user_group']),
                  _infoRow(
                    Icons.badge_outlined,
                    'Licence',
                    user['license_type'],
                  ),
                  _infoRow(
                    Icons.schedule_outlined,
                    'H/jour',
                    user['position_hours_per_day'] != null
                        ? '${user['position_hours_per_day']}h'
                        : null,
                  ),
                  _infoRow(
                    Icons.fingerprint,
                    'ID Napta',
                    user['id']?.toString(),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Fermer',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.white38),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear only session-specific data to preserve local comments and credentials
    await prefs.remove('naptaSession');
    await prefs.remove('dayRecordsData');
    await prefs.remove('dayStatusesData');
    await prefs.remove('categoriesData');

    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (e) {
      // Ignore cookie clearing errors
    }

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _syncFromNapta() async {
    final session = widget.naptaSession;
    final userId = widget.naptaUser?['userId']?.toString();
    if (session == null || userId == null || userId == 'null') return;

    setState(() => _isSyncing = true);
    try {
      final service = NaptaService(sessionCookie: session);
      final syncMonth = _currentMonth;

      // Refresh categories from Napta projects
      final projects = await service.getUserProjects(userId);
      await _saveProjectsAsCategories(projects);

      // Refresh day records for the viewed month
      final data = await service.getMonthlyDayRecords(
        userId,
        year: syncMonth.year,
        month: syncMonth.month,
      );

      // Merge — update local state first
      setState(() {
        _dayRecords.addAll(data.records);
        _dayStatuses.addAll(data.statuses);
      });

      // Persist merged data
      await _prefs.setString('dayRecordsData', jsonEncode(_dayRecords));
      await _prefs.setString('dayStatusesData', jsonEncode(_dayStatuses));

      // Merge locked holiday categories into categoriesData
      await _mergeLockedCategories(data.records);

      // Reload to ensure categories and UI are in sync
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Synchronisation Napta réussie ✓'),
            backgroundColor: Colors.green.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de synchronisation: $e'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _saveToNapta() async {
    final session = widget.naptaSession;
    final userId = widget.naptaUser?['userId']?.toString();
    if (session == null || userId == null || userId == 'null') return;

    setState(() => _isSaving = true);
    try {
      final service = NaptaService(sessionCookie: session);

      // Only send days that have been modified
      final Map<String, Map<String, double>> toSave = {};
      DateTime? minDate;
      DateTime? maxDate;

      for (final dateStr in _modifiedDates) {
        toSave[dateStr] = _dayRecords[dateStr] ?? {};
        final d = DateTime.parse(dateStr);
        if (minDate == null || d.isBefore(minDate)) minDate = d;
        if (maxDate == null || d.isAfter(maxDate)) maxDate = d;
      }

      if (toSave.isNotEmpty && minDate != null && maxDate != null) {
        await service.saveTimesheet(
          userId: userId,
          startDate: minDate,
          endDate: maxDate,
          dayRecords: toSave,
        );
      }

      setState(() {
        _hasUnsavedChanges = false;
        _modifiedDates.clear();
      });

      // Refresh data from server to ensure UI is in sync
      _syncFromNapta();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sauvegarde Napta réussie ✓'),
            backgroundColor: Colors.amber.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de sauvegarde: $e'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submitWeekForApproval(DateTime weekStart) async {
    final session = widget.naptaSession;
    final userId = widget.naptaUser?['userId']?.toString();
    if (session == null || userId == null || userId == 'null') return;

    // The week in Napta starts on Monday and ends on Sunday
    final weekEnd = weekStart.add(const Duration(days: 6));

    setState(() => _isSaving = true);
    try {
      final service = NaptaService(sessionCookie: session);
      await service.submitForApproval(
        userId: userId,
        startDate: weekStart,
        endDate: weekEnd,
      );

      // Locally mark only filled days as pending for immediate feedback
      setState(() {
        for (int i = 0; i < 7; i++) {
          final d = weekStart.add(Duration(days: i));
          final dStr = DateFormat('yyyy-MM-dd').format(d);
          // Only update status if the day has actual records/tasks
          final records = _dayRecords[dStr] ?? {};
          if (records.isNotEmpty) {
            _dayStatuses[dStr] = 'approval_pending';
          }
        }
      });
      _saveData();

      // Refresh data from server to ensure statuses are updated
      _syncFromNapta();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Semaine soumise (${DateFormat('dd/MM').format(weekStart)} - ${DateFormat('dd/MM').format(weekEnd)}) ✓',
            ),
            backgroundColor: Colors.blueAccent.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de soumission: $e'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static Future<void> _saveProjectsAsCategories(
    List<Map<String, dynamic>> projects,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getString('categoriesData');
    List<dynamic> existing = [];
    if (existingData != null) {
      existing = jsonDecode(existingData) as List<dynamic>;
    }
    final existingIds = existing.map((c) => c['id'] as String).toSet();

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

    bool changed = false;
    for (final p in projects) {
      final id = 'napta_${p['id']}';
      if (!existingIds.contains(id)) {
        final prefix = p['client_name'] != null ? '${p['client_name']} – ' : '';
        existing.add({
          'id': id,
          'name': '$prefix${p['name']}',
          'color': palette[existing.length % palette.length],
        });
        changed = true;
      }
    }

    if (changed) {
      await prefs.setString('categoriesData', jsonEncode(existing));
    }
  }

  /// Appends locked holiday categories (bank holidays, congés) to categoriesData.
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
    return Scaffold(
      body: Stack(
        children: [
          // Vibrant Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF8A2387),
                  Color(0xFFE94057),
                  Color(0xFFF27121),
                ],
              ),
            ),
          ),
          // Decorative Blobs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purpleAccent.withValues(alpha: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purpleAccent.withValues(alpha: 0.5),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      GlassContainer(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        child: Column(
                          children: [
                            // Row 1: Navigation + user + logout
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    color: Colors.white,
                                  ),
                                  onPressed: _prevMonth,
                                ),
                                Text(
                                  DateFormat(
                                    'MMMM yyyy',
                                    'fr',
                                  ).format(_currentMonth),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                  ),
                                  onPressed: _nextMonth,
                                ),
                                const Spacer(),
                                if (widget.naptaUser != null) ...[
                                  GestureDetector(
                                    onTap: () => _showUserInfo(context),
                                    child: GlassContainer(
                                      blur: 8,
                                      opacity: 0.15,
                                      borderRadius: BorderRadius.circular(12),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.person_rounded,
                                            color: Colors.white70,
                                            size: 15,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            () {
                                              final u = widget.naptaUser!;
                                              final name =
                                                  '${u['first_name'] ?? u['firstname'] ?? ''} ${u['last_name'] ?? u['lastname'] ?? ''}'
                                                      .trim();
                                              return name.isNotEmpty
                                                  ? name
                                                  : (u['email'] ??
                                                        'Utilisateur');
                                            }(),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.expand_more_rounded,
                                            color: Colors.white38,
                                            size: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ], // end if (naptaUser != null)
                                // Save button
                                if (_hasUnsavedChanges) ...[
                                  Tooltip(
                                    message:
                                        'Enregistrer les modifications sur Napta',
                                    child: GestureDetector(
                                      onTap: _isSaving ? null : _saveToNapta,
                                      child: GlassContainer(
                                        blur: 8,
                                        opacity: 0.3,
                                        color: Colors.amberAccent,
                                        borderRadius: BorderRadius.circular(12),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_isSaving)
                                              const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white70,
                                                    ),
                                              )
                                            else
                                              const Icon(
                                                Icons.cloud_upload_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Sauvegarder',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // Sync button
                                Tooltip(
                                  message: 'Synchroniser avec Napta',
                                  child: GestureDetector(
                                    onTap: _isSyncing ? null : _syncFromNapta,
                                    child: GlassContainer(
                                      blur: 8,
                                      opacity: 0.15,
                                      borderRadius: BorderRadius.circular(12),
                                      padding: const EdgeInsets.all(8),
                                      child: _isSyncing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white70,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.sync_rounded,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Déconnexion',
                                  icon: const Icon(
                                    Icons.logout,
                                    color: Colors.white60,
                                    size: 20,
                                  ),
                                  onPressed: _logout,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Row 2: Actions + total
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.15,
                                    ),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _openCategoryManager,
                                  icon: const Icon(Icons.category, size: 16),
                                  label: const Text(
                                    'Catégories',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.15,
                                    ),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _goToToday,
                                  child: const Text(
                                    "Aujourd'hui",
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Total : ${_currentMonthTotal.toStringAsFixed(2)} JH',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Calendar
                      Expanded(
                        child: GlassContainer(
                          padding: const EdgeInsets.all(24),
                          borderRadius: BorderRadius.circular(32),
                          child: CalendarGrid(
                            currentMonth: _currentMonth,
                            dayRecords: _dayRecords,
                            dayStatuses: _dayStatuses,
                            dayComments: _dayComments,
                            categories: _categories,
                            onDayDataChanged: _onDayDataChanged,
                            onSubmitWeek: _submitWeekForApproval,
                          ),
                        ),
                      ),
                    ],
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
