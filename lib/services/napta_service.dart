import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class NaptaService {
  static const String _baseUrl = 'https://app.napta.io';
  String sessionCookie;

  NaptaService({required this.sessionCookie});

  static Future<String?>? _ongoingRelogin;

  Future<http.Response> _sendRequest(
    Future<http.Response> Function() requestFn,
  ) async {
    var response = await requestFn();

    if (response.statusCode == 401 || response.statusCode == 403) {
      // Session expired/invalid, try auto relogin
      final success = await _tryAutoRelogin();
      if (success) {
        // Retry the request with the new cookie
        response = await requestFn();
      }
    }

    return response;
  }

  Future<bool> _tryAutoRelogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('napta_email');
      final password = prefs.getString('napta_password');

      if (email == null || email.isEmpty || password == null || password.isEmpty) {
        return false;
      }

      // Check if there is already an ongoing relogin
      _ongoingRelogin ??= _performSilentLogin(email, password);
      final newCookie = await _ongoingRelogin;
      _ongoingRelogin = null;

      if (newCookie != null && newCookie.isNotEmpty) {
        sessionCookie = newCookie;
        await prefs.setString('naptaSession', newCookie);
        return true;
      }
    } catch (_) {
      _ongoingRelogin = null;
    }
    return false;
  }

  Future<String?> _performSilentLogin(String email, String password) async {
    final completer = Completer<String?>();
    HeadlessInAppWebView? headlessWebView;

    // Clear cookies first to ensure fresh login
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri("https://app.napta.io/login")),
      onLoadStop: (controller, url) async {
        if (url != null && url.toString().contains('/login')) {
          final emailJson = jsonEncode(email);
          final passwordJson = jsonEncode(password);
          final js = """
            (function() {
              var hasClicked = false;
              function runStep() {
                if (hasClicked) return;
                try {
                  var emailInput = document.getElementById('email');
                  var passwordInput = document.getElementById('password');
                  if (emailInput && emailInput.offsetParent !== null && !passwordInput) {
                    emailInput.value = $emailJson;
                    emailInput.dispatchEvent(new Event('input', { bubbles: true }));
                    var nextBtn = document.getElementsByClassName('napta-button')[0];
                    if (nextBtn && nextBtn.offsetParent !== null) {
                      hasClicked = true;
                      nextBtn.click();
                    }
                  } else if (passwordInput && passwordInput.offsetParent !== null) {
                    passwordInput.value = $passwordJson;
                    passwordInput.dispatchEvent(new Event('input', { bubbles: true }));
                    var loginBtn = document.getElementsByClassName('_button-login-password')[0];
                    if (loginBtn && loginBtn.offsetParent !== null) {
                      hasClicked = true;
                      loginBtn.click();
                    }
                  }
                } catch (e) {}
              }
              runStep();
              setTimeout(runStep, 500);
              setTimeout(runStep, 1500);
            })();
          """;
          await controller.evaluateJavascript(source: js);
        }

        // Check for cookie
        final cookie = await CookieManager.instance().getCookie(
          url: WebUri("https://app.napta.io"),
          name: "naptaSession",
        );
        if (cookie != null && cookie.value != null) {
          if (!completer.isCompleted) {
            completer.complete(cookie.value.toString());
          }
        }
      },
    );

    await headlessWebView.run();

    final result = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => null,
    );

    try {
      await headlessWebView.dispose();
    } catch (_) {}

    return result;
  }

  Map<String, String> get _headers => {
    'accept': '*/*',
    'accept-language': 'fr-FR,fr;q=0.7',
    'cookie': 'naptaSession=$sessionCookie',
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
    'referer': 'https://app.napta.io/',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-origin',
  };

  /// Validate the session cookie and return the current user's info.
  Future<Map<String, dynamic>> whoAmI() async {
    final uri = Uri.parse('$_baseUrl/whoami');

    final response = await _sendRequest(() => http.get(uri, headers: _headers));


    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw NaptaAuthException(
        'Session expirée ou invalide. Veuillez vous reconnecter.',
      );
    } else {
      throw NaptaException('Erreur serveur (${response.statusCode}).');
    }
  }

  /// Fetch rich user profile (position, BU, location, group).
  /// [userId] is the numeric user ID string returned by whoAmI.
  Future<Map<String, dynamic>> getUserDetails(String userId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/v1/user/$userId'
      '?include=user_position,user_group,business_unit,location,user_config'
      '&fields[user]=active,first_name,last_name,picture,created_on,'
      'user_group_id,user_group,email,has_picture,business_unit,location,'
      'user_position,user_config,first_login_on,applicable_weekmask,is_vip',
    );


    final response = await _sendRequest(() {
      final jsonApiHeaders = {
        ..._headers,
        'accept': 'application/vnd.api+json',
        'referer': 'https://app.napta.io/timesheet',
      };
      return http.get(uri, headers: jsonApiHeaders);
    });


    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseUserDetails(json);
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw NaptaAuthException('Session expirée ou invalide.');
    } else {
      throw NaptaException('Erreur serveur (${response.statusCode}).');
    }
  }

  /// Flatten the JSON:API response into a simple map for the UI.
  Map<String, dynamic> _parseUserDetails(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final attrs = data['attributes'] as Map<String, dynamic>;
    final included = (json['included'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    Map<String, dynamic>? findIncluded(String type) {
      try {
        final match = included.firstWhere((e) => e['type'] == type);
        return match['attributes'] as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }

    final position = findIncluded('user_position');
    final businessUnit = findIncluded('business_unit');
    final location = findIncluded('location');
    final userGroup = findIncluded('user_group');

    return {
      'id': data['id'],
      'userId': data['id'], // alias so naptaUser['userId'] works everywhere
      'first_name': attrs['first_name'],
      'last_name': attrs['last_name'],
      'email': attrs['email'],
      'picture': attrs['picture'],
      'active': attrs['active'],
      'is_vip': attrs['is_vip'],
      'created_on': attrs['created_on'],
      'first_login_on': attrs['first_login_on'],
      'applicable_weekmask': attrs['applicable_weekmask'],
      'position': position?['name'],
      'position_hours_per_day': position?['hours_per_day'],
      'business_unit': businessUnit?['name'],
      'location': location?['name'],
      'location_country': location?['country_code'],
      'user_group': userGroup?['name'],
      'license_type': userGroup?['license_type'],
    };
  }

  /// Fetch all projects visible in the user's current-month timesheet.
  /// Step 1: call reporting for the full month to discover project IDs.
  /// Step 2: fetch project details with the browser URL pattern.
  Future<List<Map<String, dynamic>>> getUserProjects(String userId,
      {int? year, int? month}) async {
    final targetYear = year ?? DateTime.now().year;
    final targetMonth = month ?? DateTime.now().month;
    final reportJson = await _fetchReporting(
      userId,
      year: targetYear,
      month: targetMonth,
    );

    // Extract project IDs from total.values[userId].detailed_timesheet_values
    final total = reportJson['total'] as Map<String, dynamic>?;
    final userTotals = total?['values'] as Map<String, dynamic>?;
    final userEntry = userTotals?[userId] as Map<String, dynamic>?;
    final tsValues =
        (userEntry?['detailed_timesheet_values'] as List<dynamic>?) ?? [];

    final projectIds = tsValues
        .cast<Map<String, dynamic>>()
        .where((e) => e['object_type'] == 'project' && e['object_id'] != null)
        .map((e) => e['object_id'].toString())
        .toSet()
        .toList();


    if (projectIds.isEmpty) return [];

    return _fetchProjectDetails(projectIds);
  }

  /// New: Search projects by keyword using the Napta search API.
  Future<List<Map<String, dynamic>>> searchProjects(String query) async {
    final uri = Uri.parse('$_baseUrl/api/v1/search');
    final body = {
      "key": query,
      "mode": {
        "project": {
          "input_types": ["project", "client"],
          "extra_filters": [
            {"is_archived": false, "timesheeting_activated": [true, null]}
          ],
          "excluded_ids": [305, 306, 358, 359, 361, 363, 409]
        }
      },
      "page_number": 0
    };

    final resp = await _sendRequest(() => http.post(
      uri,
      headers: {
        ..._headers,
        'accept': '*/*',
        'content-type': 'application/json',
        'referer': 'https://app.napta.io/timesheet',
      },
      body: jsonEncode(body),
    ));


    if (resp.statusCode != 200) {
      throw NaptaException('Erreur recherche projects (${resp.statusCode}).');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>).cast<Map<String, dynamic>>();
    
    final projectIds = results.map((r) => r['id'].toString()).toList();
    if (projectIds.isEmpty) return [];

    return _fetchProjectDetails(projectIds);
  }

  /// Step 2: fetch project details — exact URL pattern from the browser
  Future<List<Map<String, dynamic>>> _fetchProjectDetails(List<String> projectIds) async {
    final projUri = Uri(
      scheme: 'https',
      host: 'app.napta.io',
      path: '/api/v1/project',
      queryParameters: {
        'fields[client]': 'name',
        'fields[project]': 'name,client',
        'include': 'client',
        'filter': '[{"name":"id","op":"in_","val":${jsonEncode(projectIds)}}]',
        'sort': 'client.name',
        'page[size]': '${projectIds.length}',
        'page[number]': '1',
      },
    );

    final projResp = await _sendRequest(() {
      final jsonApiHeaders = {
        ..._headers,
        'accept': 'application/vnd.api+json',
        'referer': 'https://app.napta.io/timesheet',
      };
      return http.get(projUri, headers: jsonApiHeaders);
    });

    if (projResp.statusCode != 200) {
      throw NaptaException('Erreur serveur projects (${projResp.statusCode}).');
    }

    return _parseProjects(jsonDecode(projResp.body) as Map<String, dynamic>);
  }

  /// Returns per-day data (records and statuses) for the given month.
  Future<({Map<String, Map<String, double>> records, Map<String, String> statuses})> 
  getMonthlyDayRecords(
    String userId, {
    required int year,
    required int month,
  }) async {
    final reportJson = await _fetchReporting(userId, year: year, month: month);

    final reports = (reportJson['reports'] as Map<String, dynamic>?) ?? {};
    final records = <String, Map<String, double>>{};
    final statuses = <String, String>{};

    for (final entry in reports.entries) {
      final dateStr = entry.key;
      final dayData = entry.value as Map<String, dynamic>;
      final userEntry =
          ((dayData['values'] as Map<String, dynamic>?)?[userId])
              as Map<String, dynamic>?;

      final status = userEntry?['status'] as String?;
      if (status != null) {
        statuses[dateStr] = status;
      }

      // "prefilled" = Napta auto-filled from planning, not a real timesheet entry.
      if (status == 'prefilled' || status == null) continue;

      final tsValues =
          (userEntry!['detailed_timesheet_values'] as List<dynamic>?) ?? [];

      final dayRecords = <String, double>{};
      for (final tsVal in tsValues.cast<Map<String, dynamic>>()) {
        final type = tsVal['object_type'] as String?;
        final actual = tsVal['actual'] != null
            ? (tsVal['actual'] as num).toDouble()
            : 0.0;
        if (actual <= 0) continue;

        if (type == 'project' && tsVal['object_id'] != null) {
          dayRecords['napta_${tsVal['object_id']}'] = actual;
        } else if (type == 'bank_holiday') {
          dayRecords['napta_bank_holiday'] = actual;
        } else if (type == 'holiday_category' && tsVal['object_id'] != null) {
          dayRecords['napta_holiday_${tsVal['object_id']}'] = actual;
        }
      }

      if (dayRecords.isNotEmpty) records[dateStr] = dayRecords;
    }

    return (records: records, statuses: statuses);
  }

  /// Scans [dayRecords] for holiday keys and returns locked Category descriptors
  /// ready to be merged into the saved categoriesData.
  static List<Map<String, dynamic>> buildLockedCategories(
    Map<String, Map<String, double>> dayRecords,
  ) {
    final seen = <String>{};
    for (final dayMap in dayRecords.values) {
      for (final key in dayMap.keys) {
        if (key == 'napta_bank_holiday' || key.startsWith('napta_holiday_')) {
          seen.add(key);
        }
      }
    }
    return seen.map((id) {
      if (id == 'napta_bank_holiday') {
        return {
          'id': id,
          'name': 'Jour Férié',
          'color': 0xFFFFA000, // amber
          'isLocked': true,
        };
      }
      return {
        'id': id,
        'name': 'Congé / Absence',
        'color': 0xFF5C6BC0, // indigo
        'isLocked': true,
      };
    }).toList();
  }

  /// Shared helper that POSTs to the reporting endpoint for a full calendar month.
  Future<Map<String, dynamic>> _fetchReporting(
    String userId, {
    required int year,
    required int month,
  }) async {
    final startDate = _fmtDate(DateTime(year, month, 1));
    final endDate = _fmtDate(DateTime(year, month + 1, 0)); // last day

    final uri = Uri(
      scheme: 'https',
      host: 'app.napta.io',
      path: '/api/v1/timesheet_new/reporting',
    );

    final resp = await _sendRequest(() => http.post(
      uri,
      headers: {
        ..._headers,
        'accept': '*/*',
        'content-type': 'application/json',
        'referer': 'https://app.napta.io/timesheet',
      },
      body: jsonEncode({
        'user_id': userId,
        'start_date': startDate,
        'end_date': endDate,
        'filters': {},
        'page_number': 0,
        'time_mode': 'day',
        'prefill_timesheets': true,
      }),
    ));


    if (resp.statusCode != 200) {
      throw NaptaException('Erreur timesheet reporting (${resp.statusCode}).');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Parse JSON:API project list response into flat maps.
  List<Map<String, dynamic>> _parseProjects(Map<String, dynamic> json) {
    final data = (json['data'] as List<dynamic>).cast<Map<String, dynamic>>();
    final included = ((json['included'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    // Build client id -> name lookup
    final clients = <String, String>{};
    for (final item in included) {
      if (item['type'] == 'client') {
        final id = item['id'] as String;
        final name =
            (item['attributes'] as Map<String, dynamic>)['name'] as String?;
        if (name != null) clients[id] = name;
      }
    }

    return data.map((project) {
      final attrs = project['attributes'] as Map<String, dynamic>;
      final rels = project['relationships'] as Map<String, dynamic>?;
      final clientId = rels?['client']?['data']?['id'] as String?;
      return {
        'id': project['id'] as String,
        'name': attrs['name'] as String,
        'client_name': clientId != null ? clients[clientId] : null,
      };
    }).toList();
  }

  /// Save timesheet data back to Napta.
  Future<void> saveTimesheet({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, Map<String, double>> dayRecords,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/timesheet_new/save');

    final workedDurations = <String, dynamic>{};

    dayRecords.forEach((dateStr, dayData) {
      final userRecords = <Map<String, dynamic>>[];
      dayData.forEach((catId, value) {
        // Only include actual projects (exclude locked holiday categories)
        if (catId.startsWith('napta_') &&
            !catId.contains('holiday') &&
            catId != 'napta_bank_holiday') {
          final projectIdStr = catId.replaceFirst('napta_', '');
          final projectId = int.tryParse(projectIdStr);
          if (projectId != null) {
            userRecords.add({
              'project_id': projectId,
              'value': value,
            });
          }
        }
      });

      // Napta expects: { "date": { "userId": [ {project_id, value} ] } }
      workedDurations[dateStr] = {userId: userRecords};
    });

    workedDurations['total'] = {};

    final body = {
      'view_start_date': _fmtDate(startDate),
      'view_end_date': _fmtDate(endDate),
      'start_date': _fmtDate(startDate),
      'end_date': _fmtDate(endDate),
      'user_ids': [int.parse(userId)],
      'worked_durations_per_user_per_period': workedDurations,
      'time_mode': 'day',
      'prefill_timesheets': true,
    };

    final resp = await _sendRequest(() => http.post(
      uri,
      headers: {
        ..._headers,
        'accept': '*/*',
        'content-type': 'application/json',
        'referer': 'https://app.napta.io/timesheet',
      },
      body: jsonEncode(body),
    ));


    if (resp.statusCode != 200) {
      throw NaptaException('Erreur sauvegarde timesheet (${resp.statusCode}).');
    }
  }

  /// Submit a specific week for approval.
  Future<void> submitForApproval({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/timesheet_new/submit_for_approval');
    final dateStrStart = _fmtDate(startDate);
    final dateStrEnd = _fmtDate(endDate);

    final body = {
      'time_mode': 'day',
      'user_ids': [int.parse(userId)],
      'start_date': dateStrStart,
      'end_date': dateStrEnd,
      'view_start_date': dateStrStart,
      'view_end_date': dateStrEnd,
      'prefill_timesheets': true,
    };

    final resp = await _sendRequest(() => http.post(
      uri,
      headers: {
        ..._headers,
        'accept': '*/*',
        'content-type': 'application/json',
        'referer': 'https://app.napta.io/timesheet',
      },
      body: jsonEncode(body),
    ));


    if (resp.statusCode != 200) {
      throw NaptaException(
        'Erreur soumission approbation (${resp.statusCode}).',
      );
    }
  }
}

class NaptaException implements Exception {
  final String message;
  NaptaException(this.message);

  @override
  String toString() => message;
}

class NaptaAuthException extends NaptaException {
  NaptaAuthException(super.message);
}
