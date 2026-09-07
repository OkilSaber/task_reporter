import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';

/// Builds and saves a monthly CSV export of the reported time entries.
///
/// One line per (day, category) entry, fields separated by `;`:
/// `id catégorie;nom catégorie;YYYY/MM/DD;commentaire;durée entrée`
class CsvExportService {
  static const String separator = ';';

  /// Builds the CSV content for [month] out of [dayRecords].
  ///
  /// Only entries with a strictly positive duration are exported. Days are
  /// ordered chronologically, and within a day the categories follow the
  /// order of the [categories] list (unknown ids last, keyed by id).
  static String buildMonthCsv({
    required DateTime month,
    required Map<String, Map<String, double>> dayRecords,
    required Map<String, String> dayComments,
    required List<Category> categories,
  }) {
    final catNames = {for (final c in categories) c.id: c.name};
    final catOrder = {
      for (var i = 0; i < categories.length; i++) categories[i].id: i,
    };

    final dateStrs = dayRecords.keys.where((dateStr) {
      final date = DateTime.tryParse(dateStr);
      return date != null &&
          date.year == month.year &&
          date.month == month.month;
    }).toList()..sort();

    final lines = <String>[];
    for (final dateStr in dateStrs) {
      final date = DateTime.parse(dateStr);
      final formattedDate = DateFormat('yyyy/MM/dd').format(date);
      final comment = dayComments[dateStr] ?? '';

      final catIds =
          dayRecords[dateStr]!.entries
              .where((e) => e.value > 0)
              .map((e) => e.key)
              .toList()
            ..sort((a, b) {
              final orderA = catOrder[a] ?? categories.length;
              final orderB = catOrder[b] ?? categories.length;
              return orderA != orderB
                  ? orderA.compareTo(orderB)
                  : a.compareTo(b);
            });

      for (final catId in catIds) {
        lines.add(
          [
            catId,
            catNames[catId] ?? catId,
            formattedDate,
            comment,
            _formatDuration(dayRecords[dateStr]![catId]!),
          ].map(_escapeField).join(separator),
        );
      }
    }

    return lines.isEmpty ? '' : '${lines.join('\r\n')}\r\n';
  }

  /// Suggested file name, e.g. `task_reporter_2026-09.csv`.
  static String fileNameFor(DateTime month) =>
      'task_reporter_${DateFormat('yyyy-MM').format(month)}.csv';

  /// Asks the user where to save the export and writes [csv] there.
  ///
  /// Returns the saved file path, or null if the user cancelled.
  static Future<String?> saveCsv(String csv, {required DateTime month}) async {
    final location = await getSaveLocation(
      suggestedName: fileNameFor(month),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'], mimeTypes: ['text/csv']),
      ],
    );
    if (location == null) return null;

    final path = location.path.toLowerCase().endsWith('.csv')
        ? location.path
        : '${location.path}.csv';

    // UTF-8 BOM so Excel picks up the accents in category names and comments.
    await File(
      path,
    ).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)], flush: true);
    return path;
  }

  /// Renders a duration the way the app displays it (2 decimals, dot).
  static String _formatDuration(double value) => value.toStringAsFixed(2);

  /// RFC 4180 quoting, needed for comments containing `;`, quotes or newlines.
  static String _escapeField(String value) {
    if (value.contains(separator) ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
