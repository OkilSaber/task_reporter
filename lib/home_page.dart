import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/secure_prefs.dart';
import 'models/category.dart';
import 'screens/login_screen.dart';
import 'services/csv_export_service.dart';
import 'services/napta_service.dart';
import 'widgets/app_background.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/category_manager_dialog.dart';
import 'widgets/comment_search_dialog.dart';
import 'widgets/day_cell.dart';
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

  List<Category> _categories = [];
  Map<String, Map<String, double>> _dayRecords = {}; // dateStr -> catId -> val
  Map<String, String> _dayStatuses = {}; // dateStr -> status
  final Map<String, String> _dayComments = {}; // dateStr -> comment
  bool _isSyncing = false;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  DateTime? _lastSyncAt;
  final ValueNotifier<String?> _hoveredCategoryId = ValueNotifier(null);
  final Set<String> _fetchedMonths = {}; // 'yyyy-MM' keys already fetched
  final Set<String> _modifiedDates =
      {}; // track days changed but not yet saved to Napta

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
    _hoveredCategoryId.dispose();
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
    // Only rebuild when the calendar day actually rolls over (midnight),
    // not every minute — full-tree setState is expensive.
    var lastDay = DateUtils.dateOnly(DateTime.now());
    _todayTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) return;
      final today = DateUtils.dateOnly(DateTime.now());
      if (today != lastDay) {
        lastDay = today;
        setState(() {});
      }
    });
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();

    // Load categories
    final catsData = _prefs.getString('categoriesData');
    if (catsData != null) {
      final List<dynamic> decodedCats = jsonDecode(catsData);
      setState(() {
        _categories = decodedCats.map((c) => Category.fromJson(c)).toList();
      });
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
          onCategoriesChanged: (newCats) async {
            setState(() {
              _categories = newCats;
            });
            await _saveData();
          },
        );
      },
    );
  }

  Future<void> _openCommentSearch() async {
    final selectedDate = await showDialog<DateTime>(
      context: context,
      builder: (context) => CommentSearchDialog(dayComments: _dayComments),
    );
    if (selectedDate == null || !mounted) return;

    // Jump the calendar to the selected day's month...
    final month = DateTime(selectedDate.year, selectedDate.month, 1);
    setState(() => _currentMonth = month);
    _fetchMonthIfNeeded(month);

    // ...then open that day's dialog directly, as if the cell was tapped.
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    showDayDialog(
      context,
      date: selectedDate,
      dayRecords: _dayRecords[dateStr] ?? {},
      categories: _categories,
      dayComment: _dayComments[dateStr],
      status: _dayStatuses[dateStr],
      onChanged: (records, comment) =>
          _onDayDataChanged(selectedDate, records, comment),
    );
  }

  /// Exports the displayed month as a `;`-separated CSV file.
  Future<void> _exportMonthCsv() async {
    final csv = CsvExportService.buildMonthCsv(
      month: _currentMonth,
      dayRecords: _dayRecords,
      dayComments: _dayComments,
      categories: _categories,
    );

    if (csv.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Aucune saisie à exporter pour ce mois'),
          backgroundColor: Colors.orangeAccent.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      final path = await CsvExportService.saveCsv(csv, month: _currentMonth);
      if (path == null || !mounted) return; // cancelled
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export CSV enregistré : $path'),
          backgroundColor: Colors.green.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de l\'export CSV: $e'),
          backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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

      // Merge — other months’ records stay intact. Track whether anything new
      // actually changed so we can skip the (expensive) full re-encode + write.
      bool recordsChanged = false;
      bool statusesChanged = false;
      data.records.forEach((k, v) {
        if (_dayRecords[k] != v) recordsChanged = true;
      });
      data.statuses.forEach((k, v) {
        if (_dayStatuses[k] != v) statusesChanged = true;
      });

      setState(() {
        _dayRecords.addAll(data.records);
        _dayStatuses.addAll(data.statuses);
        _fetchedMonths.add(monthKey);
        _lastSyncAt = DateTime.now();
      });

      // Only re-encode/write the (potentially large) maps when something changed.
      if (recordsChanged) {
        await _prefs.setString('dayRecordsData', jsonEncode(_dayRecords));
      }
      if (statusesChanged) {
        await _prefs.setString('dayStatusesData', jsonEncode(_dayStatuses));
      }

      // Merge any new locked holiday categories
      await _mergeLockedCategories(data.records);
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
    await SecurePrefs.delete('naptaSession');
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
      if (mounted) setState(() => _lastSyncAt = DateTime.now());

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

  Future<void> _saveProjectsAsCategories(
    List<Map<String, dynamic>> projects,
  ) async {
    final existingIds = _categories.map((c) => c.id).toSet();

    const palette = [
      0xFF4FC3F7, // light blue
      0xFF81C784, // light green
      0xFFFFD54F, // amber
      0xFFD32F2F, // deep red
      0xFFBA68C8, // purple
      0xFF26A69A, // teal
      0xFFAD1457, // dark pink
      0xFF1976D2, // strong blue
      0xFF7E57C2, // deep purple
      0xFF388E3C, // dark green
      0xFF5D4037, // brown
      0xFF78909C, // blue grey (near-black was invisible on the dark UI)
    ];

    final newCats = <Category>[];
    for (final p in projects) {
      final id = 'napta_${p['id']}';
      if (!existingIds.contains(id)) {
        final prefix = p['client_name'] != null ? '${p['client_name']} – ' : '';
        newCats.add(
          Category(
            id: id,
            name: '$prefix${p['name']}',
            color: Color(
              palette[(_categories.length + newCats.length) % palette.length],
            ),
          ),
        );
      }
    }

    if (newCats.isNotEmpty) {
      setState(() => _categories.addAll(newCats));
      await _saveData();
    }
  }

  /// Appends locked holiday categories (bank holidays, congés) to the
  /// in-memory categories list, preserving any user-set flags on existing entries.
  Future<void> _mergeLockedCategories(
    Map<String, Map<String, double>> dayRecords,
  ) async {
    final locked = NaptaService.buildLockedCategories(dayRecords);
    if (locked.isEmpty) return;
    final existingIds = _categories.map((c) => c.id).toSet();
    final newCats = <Category>[];
    for (final cat in locked) {
      if (!existingIds.contains(cat['id'])) {
        newCats.add(Category.fromJson(cat));
      }
    }
    if (newCats.isNotEmpty) {
      setState(() => _categories.addAll(newCats));
      await _saveData();
    }
  }

  Widget _buildHeader() {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: [
          // Time navigation: month arrows and "today" belong together.
          IconButton(
            tooltip: 'Mois précédent',
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: _prevMonth,
          ),
          SizedBox(
            width: 190,
            child: Text(
              DateFormat('MMMM yyyy', 'fr').format(_currentMonth),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Mois suivant',
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: _nextMonth,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _goToToday,
            child: const Text("Aujourd'hui", style: TextStyle(fontSize: 13)),
          ),
          const Spacer(),
          // Secondary actions: icons with tooltips.
          _headerIcon(
            Icons.search,
            'Rechercher dans les notes',
            _openCommentSearch,
          ),
          _headerIcon(
            Icons.category_outlined,
            'Gérer les catégories',
            _openCategoryManager,
          ),
          _headerIcon(
            Icons.file_download_outlined,
            'Exporter le mois en CSV',
            _exportMonthCsv,
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          _buildSyncStatus(),
          const SizedBox(width: 10),
          _buildUserMenu(),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white70, size: 20),
      onPressed: onPressed,
    );
  }

  /// One status for everything Napta-related: unsent changes are loud (and
  /// clicking sends them), an up-to-date state stays discreet.
  Widget _buildSyncStatus() {
    final unsent = _modifiedDates.length;
    final busy = _isSaving || _isSyncing;
    final hasUnsent = _hasUnsavedChanges && !_isSyncing;

    final String label;
    final String tooltip;
    final VoidCallback? onTap;
    if (_isSaving) {
      label = 'Envoi…';
      tooltip = 'Envoi des modifications vers Napta';
      onTap = null;
    } else if (_isSyncing) {
      label = 'Synchronisation…';
      tooltip = 'Synchronisation avec Napta';
      onTap = null;
    } else if (hasUnsent) {
      label = unsent > 1
          ? '$unsent jours non envoyés · Sauvegarder'
          : '$unsent jour non envoyé · Sauvegarder';
      tooltip = 'Enregistrer les modifications sur Napta';
      onTap = _saveToNapta;
    } else {
      label = _lastSyncAt != null
          ? 'Synchronisé à ${DateFormat('HH:mm').format(_lastSyncAt!)}'
          : 'Synchroniser';
      tooltip = 'Synchroniser avec Napta';
      onTap = _syncFromNapta;
    }

    final color = hasUnsent ? Colors.amberAccent : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: hasUnsent ? 0.2 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: color.withValues(alpha: hasUnsent ? 0.7 : 0.15),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else if (hasUnsent)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.amberAccent,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const Icon(
                    Icons.cloud_done_outlined,
                    color: Colors.white54,
                    size: 16,
                  ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: hasUnsent ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: hasUnsent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Avatar menu: profile, sync and logout (kept away from accidental clicks).
  Widget _buildUserMenu() {
    final u = widget.naptaUser;
    final first = (u?['first_name'] ?? u?['firstname'] ?? '').toString();
    final last = (u?['last_name'] ?? u?['lastname'] ?? '').toString();
    final fullName = '$first $last'.trim();
    final initials = [
      first,
      last,
    ].where((p) => p.isNotEmpty).map((p) => p[0].toUpperCase()).join();
    const itemStyle = TextStyle(color: Colors.white, fontSize: 13);

    return PopupMenuButton<String>(
      tooltip: fullName.isNotEmpty ? fullName : 'Compte',
      color: const Color(0xFF3B1A2C),
      offset: const Offset(0, 48),
      // Default is 300 ms: too slow for a small menu.
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 150),
        reverseDuration: Duration(milliseconds: 100),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      onSelected: (value) {
        switch (value) {
          case 'profile':
            _showUserInfo(context);
          case 'background':
            showBackgroundPicker(context);
          case 'sync':
            _syncFromNapta();
          case 'logout':
            _logout();
        }
      },
      itemBuilder: (context) => [
        if (u != null) ...[
          PopupMenuItem(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName.isNotEmpty ? fullName : 'Utilisateur',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if ((u['email'] ?? '').toString().isNotEmpty)
                  Text(
                    u['email'].toString(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'profile',
            child: Row(
              children: [
                Icon(Icons.person_outline, color: Colors.white70, size: 18),
                SizedBox(width: 10),
                Text('Profil', style: itemStyle),
              ],
            ),
          ),
        ],
        const PopupMenuItem(
          value: 'background',
          child: Row(
            children: [
              Icon(Icons.palette_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text("Fond d'écran", style: itemStyle),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'sync',
          child: Row(
            children: [
              Icon(Icons.sync_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Synchroniser avec Napta', style: itemStyle),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.redAccent, size: 18),
              SizedBox(width: 10),
              Text(
                'Déconnexion',
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: initials.isNotEmpty
            ? Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              )
            : const Icon(Icons.person_rounded, color: Colors.white70, size: 18),
      ),
    );
  }

  static bool _isHolidayCategory(String catId, Set<String> lockedIds) =>
      lockedIds.contains(catId) ||
      catId == 'napta_bank_holiday' ||
      catId.startsWith('napta_holiday_');

  static String _formatDays(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Widget _buildMonthSummary() {
    final Map<String, double> categoryTotals = {};
    double grandTotal = 0;
    double holidays = 0;
    final lockedIds = _categories
        .where((c) => c.isLocked)
        .map((c) => c.id)
        .toSet();

    _dayRecords.forEach((key, dayMap) {
      try {
        final date = DateFormat('yyyy-MM-dd').parse(key);
        if (date.year == _currentMonth.year &&
            date.month == _currentMonth.month) {
          final isWeekend =
              date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday;
          dayMap.forEach((catId, val) {
            if (val > 0) {
              categoryTotals[catId] = (categoryTotals[catId] ?? 0) + val;
              grandTotal += val;
              if (!isWeekend && _isHolidayCategory(catId, lockedIds)) {
                holidays += val;
              }
            }
          });
        }
      } catch (_) {
        // Ignore parsing errors for safety
      }
    });

    // Days to fill this month: working days minus bank holidays / leave.
    final daysInMonth = DateUtils.getDaysInMonth(
      _currentMonth.year,
      _currentMonth.month,
    );
    int weekdays = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final wd = DateTime(_currentMonth.year, _currentMonth.month, d).weekday;
      if (wd != DateTime.saturday && wd != DateTime.sunday) weekdays++;
    }
    final toFill = weekdays - holidays;
    final worked = _currentMonthTotal;

    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    Category categoryFor(String id) => _categories.firstWhere(
      (c) => c.id == id,
      orElse: () => Category(
        id: id,
        name: 'Catégorie inconnue',
        color: const Color(0xFF9E9E9E),
      ),
    );

    // Month progress, split by (worked) category.
    final segments = <Widget>[];
    for (final entry in sortedEntries) {
      if (_isHolidayCategory(entry.key, lockedIds)) continue;
      if (segments.isNotEmpty) segments.add(const SizedBox(width: 1));
      segments.add(
        Expanded(
          flex: (entry.value * 100).round(),
          child: ColoredBox(color: categoryFor(entry.key).color),
        ),
      );
    }
    if (toFill > worked) {
      segments.add(
        Expanded(
          flex: ((toFill - worked) * 100).round(),
          child: const SizedBox(),
        ),
      );
    }

    final monthName = DateFormat('MMMM', 'fr').format(_currentMonth);

    return Row(
      children: [
        const SizedBox(width: 24),
        GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(32),
          child: SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      monthName[0].toUpperCase() + monthName.substring(1),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: worked.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${_formatDays(toFill)} j',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 8,
                    color: Colors.white.withValues(alpha: 0.12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: segments,
                    ),
                  ),
                ),
                if (holidays > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_formatDays(holidays)} j de congés / fériés déduits',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
                const SizedBox(height: 24),
                Expanded(
                  child: sortedEntries.isEmpty
                      ? const Text(
                          'Aucune saisie ce mois-ci.',
                          style: TextStyle(color: Colors.white54),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(right: 12),
                          itemCount: sortedEntries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = sortedEntries[index];
                            return _buildSummaryRow(
                              categoryFor(entry.key),
                              entry.value,
                              grandTotal,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(Category category, double value, double grandTotal) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hoveredCategoryId.value = category.id,
      onExit: (_) => _hoveredCategoryId.value = null,
      child: ValueListenableBuilder<String?>(
        valueListenable: _hoveredCategoryId,
        builder: (context, hovered, child) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: hovered == category.id
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: child,
          );
        },
        child: Tooltip(
          message: category.name,
          waitDuration: const Duration(milliseconds: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (category.client != null)
                          Text(
                            category.client!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        Row(
                          children: [
                            if (category.isLocked) ...[
                              const Icon(
                                Icons.lock_rounded,
                                size: 12,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                category.project,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${value.toStringAsFixed(2)} j',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Share of the month
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 4,
                  color: Colors.white.withValues(alpha: 0.1),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    heightFactor: 1,
                    widthFactor: grandTotal > 0
                        ? (value / grandTotal).clamp(0.0, 1.0)
                        : 0,
                    child: ColoredBox(color: category.color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AppBackground(),

          // Main Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1300),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      // Calendar and Summary
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                  highlightedCategory: _hoveredCategoryId,
                                  onDayDataChanged: _onDayDataChanged,
                                  onSubmitWeek: _submitWeekForApproval,
                                ),
                              ),
                            ),
                            // Month Summary
                            _buildMonthSummary(),
                          ],
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
